<script setup>
import { computed, ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import KanbanNotesTab from './KanbanNotesTab.vue';
import KanbanChecklistTab from './KanbanChecklistTab.vue';
import KanbanAttachmentsTab from './KanbanAttachmentsTab.vue';
import ScheduleMessageModal from 'dashboard/components/widgets/conversation/bubble/ScheduleMessageModal.vue';
import conversationAPI from '../../../../api/inbox/conversation';
import inboxAPI from '../../../../api/inboxes';

// Definição dos props
const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  isStacklab: {
    type: Boolean,
    default: false,
  },
  kanbanItems: {
    type: Array,
    required: true,
  },
  conversations: {
    type: Array,
    required: true,
  },
  contactsList: {
    type: Array,
    required: true,
  },
  loadingItems: {
    type: Boolean,
    default: false,
  },
  loadingConversations: {
    type: Boolean,
    default: false,
  },
  loadingContacts: {
    type: Boolean,
    default: false,
  },
  currentUser: {
    type: Object,
    required: true,
  },
  agentList: {
    type: Array,
    required: true,
  },
});

// Definição dos emits
const emit = defineEmits([
  'upload-attachment',
  'delete-attachment',
  'update-item',
  'item-updated',
  'navigate-to-conversation',
  'context-menu',
  'stage-click',
  'tab-changed',
]);

const { t } = useI18n();

// Estado das tabs
const activeTab = ref('notes');
const showDebug = ref(false);

// Só deve carregar "Mensagens agendadas" se houver conversa vinculada
const hasConversation = computed(() => {
  return Boolean(
    props.item?.conversation?.id || props.item?.item_details?.conversation?.id
  );
});

// Watcher para emitir mudança de aba
watch(activeTab, (newTab) => {
  emit('tab-changed', newTab);

  // Buscar mensagens agendadas quando a aba for ativada
  if (newTab === 'scheduled-messages') {
    fetchScheduledMessages();
  }
});

// Refs para upload de anexos
const isUploadingAttachment = ref(false);
const selectedFileName = ref('');
const MAXIMUM_FILE_UPLOAD_SIZE = 67108864; // 64MB

// Refs para busca nos modais de vinculação
const itemSearchTerm = ref('');
const conversationSearchTerm = ref('');
const contactSearchTerm = ref('');

// Estado para mensagens agendadas
const scheduledMessages = ref([]);
const loadingScheduledMessages = ref(false);
const showScheduleModal = ref(false);
const messageBeingEdited = ref(null);

// Estado para cache de inboxes
const inboxesCache = ref(new Map());

// Computed para formatar data
const formatDate = date => {
  if (!date) return '';
  try {
    return format(new Date(date), 'dd/MM/yyyy HH:mm', { locale: ptBR });
  } catch (error) {
    console.error('Erro ao formatar data:', error);
    return '';
  }
};

// Computed para histórico (mock - pode ser ajustado conforme necessidade)
const history = computed(() => {
  if (!props.item?.activities) return [];

  return props.item.activities.map(activity => ({
    id: activity.id || Date.now(),
    title: activity.type || 'Atividade',
    details: activity.details || '',
    created_at: activity.created_at,
    user: activity.user,
    icon: 'calendar-clock', // ícone padrão
  }));
});

// Computed para obter as notas do item
const notes = computed(() => {
  const itemNotes = props.item?.item_details?.notes;
  return Array.isArray(itemNotes) ? itemNotes : [];
});

// Computed filtrados
const filteredKanbanItems = computed(() => {
  if (!itemSearchTerm.value) return props.kanbanItems;
  return props.kanbanItems.filter(item =>
    (item.title || '')
      .toLowerCase()
      .includes(itemSearchTerm.value.toLowerCase())
  );
});

const filteredConversations = computed(() => {
  if (!conversationSearchTerm.value) return props.conversations;
  return props.conversations.filter(conv =>
    ((conv.title || '') + ' ' + (conv.description || ''))
      .toLowerCase()
      .includes(conversationSearchTerm.value.toLowerCase())
  );
});

const filteredContactsList = computed(() => {
  if (!contactSearchTerm.value) return props.contactsList;
  return props.contactsList.filter(contact =>
    (contact.name || '')
      .toLowerCase()
      .includes(contactSearchTerm.value.toLowerCase())
  );
});

// Array de tabs (condicional para mensagens agendadas)
const tabs = computed(() => {
  const baseTabs = [
    { id: 'notes', icon: 'document', label: t('KANBAN.TABS.NOTES') },
    {
      id: 'checklist',
      icon: 'checkmark-circle',
      label: t('KANBAN.TABS.CHECKLIST'),
    },
    { id: 'attachments', icon: 'attach', label: t('KANBAN.TABS.ATTACHMENTS') },
  ];

  if (hasConversation.value) {
    baseTabs.push({
      id: 'scheduled-messages',
      icon: 'custom-calendar-sync',
      label: 'Mensagens Agendadas',
      customSvg:
        `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-calendar-sync-icon lucide-calendar-sync"><path d="M11 10v4h4"/><path d="m11 14 1.535-1.605a5 5 0 0 1 8 1.5"/><path d="M16 2v4"/><path d="m21 18-1.535 1.605a5 5 0 0 1-8-1.5"/><path d="M21 22v-4h-4"/><path d="M21 8.5V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h4.3"/><path d="M3 10h4"/><path d="M8 2v4"/></svg>`,
    });
  }

  return baseTabs;
});

// Funções para upload de anexos
const handleNoteAttachment = file => {
  emit('upload-attachment', file);
};

const removeAttachment = attachment => {
  emit('delete-attachment', attachment);
};

// Funções para atualização de item
const handleUpdateItem = item => {
  emit('update-item', item);
};

const handleItemUpdated = () => {
  emit('item-updated');
};

// Função para buscar mensagens agendadas da conversa
const fetchScheduledMessages = async () => {
  // Só buscar se houver conversa vinculada
  const conversationId = props.item?.conversation?.id || props.item?.item_details?.conversation?.id;

  if (!conversationId) {
    scheduledMessages.value = [];
    return;
  }

  try {
    loadingScheduledMessages.value = true;
    const response = await conversationAPI.getScheduledMessages(conversationId);
    scheduledMessages.value = response.data.payload || [];

    // Pré-carrega os nomes das inboxes para melhor performance
    await preloadInboxNames();
  } catch (error) {
    console.error('Erro ao buscar mensagens agendadas:', error);
    scheduledMessages.value = [];
  } finally {
    loadingScheduledMessages.value = false;
  }
};

// Função para pré-carregar nomes das inboxes
const preloadInboxNames = async () => {
  const inboxIds = [...new Set(scheduledMessages.value.map(msg => msg.inbox_id))];

  // Remove IDs que já estão no cache
  const uncachedIds = inboxIds.filter(id => !inboxesCache.value.has(id));

  if (uncachedIds.length === 0) return;

  // Busca em lote para melhor performance
  const promises = uncachedIds.map(id => getInboxName(id));
  await Promise.allSettled(promises);
};

// Função para formatar data das mensagens agendadas
const formatScheduledDate = (timestamp) => {
  return new Date(timestamp * 1000).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
};

// Função para obter nome do inbox usando API com cache
const getInboxName = async (inboxId) => {
  if (!inboxId) return 'Inbox não encontrado';

  // Verifica se já está no cache
  if (inboxesCache.value.has(inboxId)) {
    return inboxesCache.value.get(inboxId);
  }

  try {
    // Busca da API usando o método show da inboxAPI (sem cache)
    const response = await inboxAPI.show(inboxId);
    const inboxName = response.data.name || 'Inbox não encontrado';

    // Armazena no cache
    inboxesCache.value.set(inboxId, inboxName);

    return inboxName;
  } catch (error) {
    console.error('Erro ao buscar nome da inbox:', error);
    // Fallback: tenta buscar no agentList se disponível
    const inbox = props.agentList?.find(i => i.id === inboxId);
    const fallbackName = inbox ? inbox.name : 'Inbox não encontrado';

    // Mesmo com erro, armazena no cache para evitar requests repetidas
    inboxesCache.value.set(inboxId, fallbackName);

    return fallbackName;
  }
};

// Função para obter texto do status
const getStatusText = (status) => {
  return status === 'sent' ? 'Enviado' : 'Pendente';
};

// Função para obter nome da inbox de forma síncrona (do cache)
const getInboxNameSync = (inboxId) => {
  if (!inboxId) return 'Inbox não encontrado';

  // Retorna do cache se disponível
  if (inboxesCache.value.has(inboxId)) {
    return inboxesCache.value.get(inboxId);
  }

  // Dispara busca assíncrona em background
  getInboxName(inboxId).catch(() => {
    // Ignora erros para não quebrar o rendering
  });

  // Retorna fallback enquanto busca
  const inbox = props.agentList?.find(i => i.id === inboxId);
  return inbox ? inbox.name : 'Carregando...';
};

// Funções para o modal de agendamento
const openScheduleModal = () => {
  messageBeingEdited.value = null;
  showScheduleModal.value = true;
};

const closeScheduleModal = () => {
  showScheduleModal.value = false;
  messageBeingEdited.value = null;
  // Recarregar mensagens após fechar o modal
  fetchScheduledMessages();
};

// Função para editar mensagem agendada
const editScheduledMessage = (message) => {
  messageBeingEdited.value = message;
  showScheduleModal.value = true;
};

// Função para deletar mensagem agendada
const deleteScheduledMessage = async (messageId) => {
  if (!confirm('Tem certeza que deseja excluir esta mensagem agendada?')) {
    return;
  }

  const conversationId = props.item?.conversation?.id || props.item?.item_details?.conversation?.id;
  
  try {
    await conversationAPI.deleteScheduledMessage(conversationId, messageId);
    await fetchScheduledMessages();
    // Você pode adicionar um toast de sucesso aqui se desejar
  } catch (error) {
    console.error('Erro ao deletar mensagem agendada:', error);
    alert('Erro ao excluir mensagem agendada');
  }
};
</script>

<template>
  <div class="space-y-4">
    <!-- Tabs -->
    <div
      class="tabs-container mb-6"
    >
      <div class="tabs-scroll-wrapper">
        <button
          v-for="tab in tabs"
          :key="tab.id"
          class="tab-button flex-shrink-0"
          :class="activeTab === tab.id ? 'tab-active' : 'tab-inactive'"
          @click="activeTab = tab.id"
        >
          <div class="flex items-center gap-2">
            <fluent-icon v-if="!tab.customSvg" :icon="tab.icon" size="16" />
            <span v-else v-html="tab.customSvg" class="w-4 h-4 flex-shrink-0"></span>
            {{ tab.label }}
          </div>
        </button>
      </div>
    </div>

    <!-- Conteúdo das Tabs -->
    <div class="space-y-6">

      <!-- Tab de Notas -->
      <div v-if="activeTab === 'notes'">
        <KanbanNotesTab
          :item="item"
          :notes="notes"
          :is-stacklab="isStacklab"
          :kanban-items="filteredKanbanItems"
          :conversations="filteredConversations"
          :contacts-list="filteredContactsList"
          :loading-items="loadingItems"
          :loading-conversations="loadingConversations"
          :loading-contacts="loadingContacts"
          :current-user="currentUser"
          @upload-attachment="handleNoteAttachment"
          @delete-attachment="removeAttachment"
        />
      </div>

      <!-- Tab de Checklist -->
      <div v-if="activeTab === 'checklist'">
        <KanbanChecklistTab
          :item="item"
          :is-stacklab="isStacklab"
          :kanban-items="filteredKanbanItems"
          :conversations="filteredConversations"
          :contacts-list="filteredContactsList"
          :loading-items="loadingItems"
          :loading-conversations="loadingConversations"
          :loading-contacts="loadingContacts"
          :current-user="currentUser"
          :agent-list="agentList"
          @item-updated="handleItemUpdated"
          @upload-attachment="handleNoteAttachment"
          @delete-attachment="removeAttachment"
        />
      </div>

      <!-- Tab de Anexos -->
      <div v-if="activeTab === 'attachments'">
        <KanbanAttachmentsTab
          :item="item"
          :is-stacklab="isStacklab"
        />
      </div>

      <!-- Tab de Mensagens Agendadas -->
      <div v-if="hasConversation && activeTab === 'scheduled-messages'">
        <div class="scheduled-messages-container">
          <!-- Header com botão de agendar -->
          <div class="scheduled-messages-header">
            <button
              class="schedule-button"
              @click="openScheduleModal"
            >
              <fluent-icon icon="add" size="16" />
              Agendar Mensagem
            </button>
          </div>
          <!-- Estado de carregamento -->
          <div v-if="loadingScheduledMessages" class="flex justify-center items-center py-8">
            <span class="w-6 h-6 border-2 border-t-woot-500 border-r-woot-500 border-b-transparent border-l-transparent rounded-full animate-spin" />
          </div>

          <!-- Estado vazio -->
          <div v-else-if="scheduledMessages.length === 0" class="empty-state">
            <div class="empty-state-content">
              <svg
                width="32"
                height="32"
                fill="none"
                viewBox="0 0 24 24"
                xmlns="http://www.w3.org/2000/svg"
                class="empty-icon"
              >
                <path
                  d="M17.75 3A3.25 3.25 0 0 1 21 6.25v11.5A3.25 3.25 0 0 1 17.75 21H6.25A3.25 3.25 0 0 1 3 17.75V6.25A3.25 3.25 0 0 1 6.25 3h11.5Zm1.75 5.5h-15v9.25c0 .966.784 1.75 1.75 1.75h11.5a1.75 1.75 0 0 0 1.75-1.75V8.5Zm-11.75 6a1.25 1.25 0 1 1 0 2.5a1.25 1.25 0 0 1 0-2.5Zm4.25 0a1.25 1.25 0 1 1 0 2.5a1.25 1.25 0 0 1 0-2.5Zm-4.25-4a1.25 1.25 0 1 1 0 2.5a1.25 1.25 0 0 1 0-2.5Zm4.25 0a1.25 1.25 0 1 1 0 2.5a1.25 1.25 0 0 1 0-2.5Zm4.25 0a1.25 1.25 0 1 1 0 2.5a1.25 1.25 0 0 1 0-2.5Zm1.5-6H6.25A1.75 1.75 0 0 0 4.5 6.25V7h15v-.75a1.75 1.75 0 0 0-1.75-1.75Z"
                  fill="currentColor"
                />
              </svg>
              <p class="empty-text">Nenhuma mensagem agendada</p>
              <p class="empty-subtext">
                As mensagens agendadas desta conversa aparecerão aqui
              </p>
            </div>
          </div>

          <!-- Lista de mensagens agendadas -->
          <div v-else class="scheduled-messages-list">
            <div
              v-for="message in scheduledMessages"
              :key="message.id"
              class="scheduled-message-card"
            >
              <!-- Card principal com design refinado -->
              <div class="bg-white dark:bg-slate-800 rounded-xl p-6 border border-slate-100 dark:border-slate-700 shadow-sm hover:shadow-md transition-all duration-200 hover:-translate-y-0.5">
                <!-- Header com indicador visual -->
                <div class="flex items-center justify-between mb-4">
                  <div class="flex items-center gap-3">
                    <div class="relative">
                      <!-- Indicador animado baseado no status -->
                      <div
                        class="w-3 h-3 rounded-full animate-pulse"
                        :class="{
                          'bg-woot-500': message.status === 'pending',
                          'bg-green-500': message.status === 'sent'
                        }"
                      ></div>
                      <!-- Animação de pulso adicional para mensagens pendentes -->
                      <div
                        v-if="message.status === 'pending'"
                        class="absolute inset-0 w-3 h-3 bg-woot-500 rounded-full animate-ping opacity-20"
                      ></div>
                    </div>
                    <div>
                      <h3 class="text-sm font-semibold text-slate-900 dark:text-slate-100 leading-tight">
                        {{ message.title }}
                      </h3>
                      <div class="flex items-center gap-2 mt-1">
                        <!-- Status badge refinado -->
                        <span
                          class="inline-flex items-center px-2.5 py-1 text-xs font-medium rounded-full border"
                          :class="{
                            'bg-woot-50 text-woot-700 border-woot-200 dark:bg-woot-900/30 dark:text-woot-300 dark:border-woot-800':
                              message.status === 'pending',
                            'bg-green-50 text-green-700 border-green-200 dark:bg-green-900/30 dark:text-green-300 dark:border-green-800':
                              message.status === 'sent'
                          }"
                        >
                          <span class="w-1.5 h-1.5 bg-current rounded-full mr-1.5 animate-pulse" v-if="message.status === 'pending'"></span>
                          {{ getStatusText(message.status) }}
                        </span>

                        <!-- Badge de recorrência -->
                        <span
                          v-if="message.is_recurrent"
                          class="inline-flex items-center px-2 py-1 text-xs font-medium bg-blue-50 text-blue-700 border border-blue-200 rounded-full dark:bg-blue-900/30 dark:text-blue-300 dark:border-blue-800"
                        >
                          <fluent-icon icon="arrow-clockwise" size="10" class="mr-1" />
                          Recorrente
                        </span>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Metadados organizados -->
                <div class="grid grid-cols-1 gap-3 mb-4">
                  <!-- Data e hora -->
                  <div class="flex items-center gap-2 text-xs text-slate-600 dark:text-slate-400">
                    <div class="flex items-center justify-center w-5 h-5 bg-slate-100 dark:bg-slate-700 rounded-md">
                      <fluent-icon icon="calendar" size="12" class="text-slate-500 dark:text-slate-400" />
                    </div>
                    <span class="font-medium">{{ formatScheduledDate(message.scheduled_at) }}</span>
                  </div>

                  <!-- Canal/Inbox -->
                  <div class="flex items-center gap-2 text-xs text-slate-600 dark:text-slate-400">
                    <div class="flex items-center justify-center w-5 h-5 bg-slate-100 dark:bg-slate-700 rounded-md">
                      <fluent-icon icon="chat" size="12" class="text-slate-500 dark:text-slate-400" />
                    </div>
                    <span class="font-medium">{{ getInboxNameSync(message.inbox_id) }}</span>
                  </div>
                </div>

                <!-- Conteúdo da mensagem -->
                <div class="bg-slate-50 dark:bg-slate-700/50 rounded-lg p-4">
                  <div class="flex items-start gap-3">
                    <div class="flex items-center justify-center w-6 h-6 bg-woot-100 dark:bg-woot-900/50 rounded-md flex-shrink-0 mt-0.5">
                      <fluent-icon icon="chat" size="14" class="text-woot-600 dark:text-woot-400" />
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm text-slate-700 dark:text-slate-300 leading-relaxed whitespace-pre-wrap">
                        {{ message.message }}
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Ações sutis no footer -->
                <div class="flex justify-end gap-2 mt-4 pt-4 border-t border-slate-100 dark:border-slate-700">
                  <button
                    class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-700/50 rounded-md transition-colors"
                    @click="editScheduledMessage(message)"
                  >
                    <fluent-icon icon="edit" size="12" />
                    Editar
                  </button>
                  <button
                    class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-700/50 rounded-md transition-colors"
                    @click="deleteScheduledMessage(message.id)"
                  >
                    <fluent-icon icon="delete" size="12" />
                    Excluir
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

    </div>
  </div>

  <!-- Modal de Agendamento de Mensagem -->
  <ScheduleMessageModal
    v-if="hasConversation"
    :show="showScheduleModal"
    :conversation-id="item?.conversation?.id || item?.item_details?.conversation?.id"
    :editing-message="messageBeingEdited"
    @close="closeScheduleModal"
  />
</template>

<style scoped>
.tabs-container {
  margin-bottom: 1rem;
}

.tab-button.tab-active {
  @apply text-woot-500;
}

.tab-button.tab-active::after {
  content: '';
  @apply absolute bottom-0 left-0 right-0 h-0.5 bg-woot-500;
}

.tab-button.tab-inactive {
  @apply text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-100;
}

.tab-inactive:hover {
  color: #64748b;
}

.dark .tab-inactive {
  color: #94a3b8;
}

.dark .tab-inactive:hover {
  color: #64748b;
}

/* Estilos para as abas com scroll lateral */
.tabs-container {
  overflow: hidden;
}

.tabs-scroll-wrapper {
  display: flex;
  overflow-x: auto;
  scrollbar-width: none; /* Firefox */
  -ms-overflow-style: none; /* IE and Edge */
  scroll-behavior: smooth;
}

.tabs-scroll-wrapper::-webkit-scrollbar {
  display: none; /* Chrome, Safari and Opera */
}

.tab-button {
  @apply px-4 py-2 text-sm font-medium relative transition-colors whitespace-nowrap;
}

/* Mobile: ajustes específicos para abas */
@media (max-width: 768px) {
  .tab-button {
    @apply px-3 py-2 text-xs;
  }

  .tabs-scroll-wrapper {
    padding-bottom: 2px; /* Espaço para o scroll */
  }
}

/* Estilos para a aba de mensagens agendadas */
.scheduled-messages-container {
  @apply space-y-4;
}

.empty-state {
  @apply flex items-center justify-center py-12;
}

.empty-state-content {
  @apply text-center;
}

.empty-icon {
  @apply text-slate-400 dark:text-slate-500 mx-auto mb-4;
}

.empty-text {
  @apply text-sm font-medium text-slate-700 dark:text-slate-300 mb-2;
}

.empty-subtext {
  @apply text-xs text-slate-500 dark:text-slate-400;
}

.scheduled-messages-list {
  @apply space-y-4;
}

.scheduled-message-card {
  animation: fade-in-up 0.5s ease-out;
}

@keyframes fade-in-up {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes card-hover-lift {
  from {
    transform: translateY(0);
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1), 0 1px 2px rgba(0, 0, 0, 0.06);
  }
  to {
    transform: translateY(-2px);
    box-shadow: 0 10px 15px rgba(0, 0, 0, 0.1), 0 4px 6px rgba(0, 0, 0, 0.05);
  }
}

@keyframes status-pulse {
  0%, 100% {
    transform: scale(1);
    opacity: 0.8;
  }
  50% {
    transform: scale(1.1);
    opacity: 1;
  }
}

/* Hover effects refinados */
.scheduled-message-card:hover .bg-white,
.scheduled-message-card:hover .dark\:bg-slate-800 {
  animation: card-hover-lift 0.2s ease-out forwards;
}

/* Animação sutil para status badges */
.status-badge {
  transition: all 0.2s ease-in-out;
}

.status-badge:hover {
  transform: scale(1.02);
}

/* Responsividade para mobile */
@media (max-width: 768px) {
  .scheduled-message-card .bg-white,
  .scheduled-message-card .dark\:bg-slate-800 {
    padding: 1rem;
    border-radius: 0.5rem;
  }

  .scheduled-message-card .grid {
    grid-template-columns: repeat(1, minmax(0, 1fr));
    gap: 0.5rem;
  }

  .scheduled-message-card .flex.justify-end.gap-2 {
    flex-direction: column;
    gap: 0.25rem;
  }

  .scheduled-message-card button {
    width: 100%;
    justify-content: center;
  }
}

/* Estilos para o header e botão de agendar */
.scheduled-messages-header {
  @apply flex justify-end mb-4;
}

.schedule-button {
  @apply inline-flex items-center gap-2 px-4 py-2 bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium rounded-md transition-colors;
}

.schedule-button:hover {
  @apply bg-woot-600;
}
</style>
