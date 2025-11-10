<script setup>
/* global axios */
import { ref, computed, watch, nextTick, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import KanbanAPI from '../../../../api/kanban';
import MarkdownIt from 'markdown-it';

// Props
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
    default: () => [],
  },
  conversations: {
    type: Array,
    default: () => [],
  },
  contactsList: {
    type: Array,
    default: () => [],
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
    default: () => [],
  },
});

// Emits
const emit = defineEmits([
  'update:checklists',
  'update:item',
  'item-updated',
  'add-checklist-item',
  'edit-checklist-item',
  'delete-checklist-item',
  'toggle-checklist-item'
]);

const { t } = useI18n();

// Instância do MarkdownIt com configurações padrão
const md = new MarkdownIt({
  html: false,      // Desabilitar HTML inline para segurança
  breaks: true,     // Converter quebras de linha em <br>
  linkify: true     // Converter URLs em links automaticamente
});

// Função para renderizar markdown
const renderMarkdown = (text) => {
  if (!text) return '';

  // Renderizar diretamente - markdown-it já suporta listas por padrão
  return md.render(text);
};

// Refs para o componente
const currentChecklistItem = ref('');
const savingChecklist = ref(false);
const editingItemId = ref(null);
const editingItemText = ref('');
const loadingChecklists = ref(false);
const internalChecklists = ref([]);


// Refs para o checklist
const hideCompletedItems = ref(false);
const checklistDueDate = ref('');
const checklistPriority = ref('none');


// Refs para atribuição de agentes aos itens do checklist
const showAgentAssignModal = ref(false);
const selectedChecklistItemForAgent = ref(null);
const agentAssignLoading = ref(false);
const selectedAgentId = ref(null);
const agentSearch = ref('');

// Refs para modal de detalhes do item
const showItemDetailsModal = ref(false);
const selectedChecklistItemDetails = ref(null);


// Computed para estatísticas do checklist
const checklistStats = computed(() => {
  const checklists = displayChecklists.value;

  const total = checklists.length;
  const completed = checklists.filter(item => item.completed).length;
  const percentage = total > 0 ? Math.round((completed / total) * 100) : 0;
  return { total, completed, percentage };
});

// Ref para controle de ordenação
const checklistSortOrder = ref('newest'); // 'newest', 'oldest'

// Computed para usar checklists internos
const displayChecklists = computed(() => {
  // Garantir que checklists seja sempre um array
  let checklists = Array.isArray(internalChecklists.value) ? internalChecklists.value : [];

  if (!checklists || checklists.length === 0) return [];

  // Ordenar checklists baseado no critério selecionado
  return [...checklists].sort((a, b) => {
    switch (checklistSortOrder.value) {
      case 'oldest':
        return new Date(a.created_at || 0) - new Date(b.created_at || 0);
      case 'newest':
      default:
        return new Date(b.created_at || 0) - new Date(a.created_at || 0);
    }
  });
});

// Computed para filtrar checklists
const filteredChecklistItems = computed(() => {
  const checklists = displayChecklists.value;

  if (hideCompletedItems.value) {
    return checklists.filter(item => !item.completed);
  }
  return checklists;
});

// Computed para obter informações do agente de um item do checklist
const getChecklistItemAgent = checklistItem => {
  if (!checklistItem.agent_id) return null;

  const agent = props.agentList.find(a => a.id === checklistItem.agent_id);
  if (!agent) return null;

  return {
    id: agent.id,
    name: agent.name,
    avatar_url: agent.avatar_url || '',
  };
};

// Computed para obter informações do autor de um item do checklist
const getChecklistItemAuthor = checklistItem => {
  if (!checklistItem.agent_id) return null;

  const author = props.agentList.find(a => a.id === checklistItem.agent_id);
  if (!author) return null;

  return {
    id: author.id,
    name: author.name,
    avatar_url: author.avatar_url || '',
  };
};

// Função para obter informações da prioridade do item do checklist
const getChecklistItemPriority = checklistItem => {
  const priority = checklistItem.priority || 'none';
  const priorityMap = {
    none: { label: 'Nenhuma', color: 'slate', iconSvg: null },
    low: { label: 'Baixa', color: 'green', iconSvg: '<path d="M7 13l3 3 3-3"/><path d="M7 6l3 3 3-3"/>' },
    medium: { label: 'Média', color: 'yellow', iconSvg: '<path d="M9 12l2 2 2-2"/><path d="M7 7l4 4 4-4"/>' },
    high: { label: 'Alta', color: 'orange', iconSvg: '<path d="M7 11l3-3 3 3"/><path d="M7 18l3-3 3 3"/>' },
    urgent: { label: 'Urgente', color: 'red', iconSvg: '<path d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"/>' }
  };

  return priorityMap[priority] || priorityMap.none;
};



const formatDate = date => {
  if (!date) return '';
  try {
    const dateObj = new Date(date);
    return dateObj.toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch (error) {
    console.error('Erro ao formatar data:', error);
    return '';
  }
};

// Funções para manipulação do checklist
const handleAddChecklistItem = async () => {
  if (!currentChecklistItem.value.trim()) return;

  try {
    await KanbanAPI.createChecklistItem(props.item?.id, {
      text: currentChecklistItem.value,
      due_date: checklistDueDate.value || null,
      priority: checklistPriority.value,
      agent_id: props.currentUser?.id,
    });

    // Buscar checklists atualizadas
    await fetchChecklists();

    // Limpar estado
    currentChecklistItem.value = '';
    checklistDueDate.value = '';
    checklistPriority.value = 'none';
    editingItemId.value = null;

    // Mostrar mensagem de sucesso
    emitter.emit('newToastMessage', {
      message: 'Item do checklist criado com sucesso',
      action: { type: 'success' },
    });

  } catch (error) {
    console.error('Erro ao adicionar item do checklist:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao criar item do checklist',
      action: { type: 'error' },
    });
  }
};

const handleUpdateChecklistItem = async () => {
  if (!currentChecklistItem.value.trim() || !editingItemId.value) return;

  try {
    await KanbanAPI.updateChecklistItem(props.item?.id, editingItemId.value, {
      text: currentChecklistItem.value,
      due_date: checklistDueDate.value || null,
      priority: checklistPriority.value,
    });

    // Buscar checklists atualizadas
    await fetchChecklists();

    // Limpar estado
    currentChecklistItem.value = '';
    checklistDueDate.value = '';
    checklistPriority.value = 'none';
    editingItemId.value = null;

    // Mostrar mensagem de sucesso
    emitter.emit('newToastMessage', {
      message: 'Item do checklist atualizado com sucesso',
      action: { type: 'success' },
    });

  } catch (error) {
    console.error('Erro ao atualizar item do checklist:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao atualizar item do checklist',
      action: { type: 'error' },
    });
  }
};


const handleEditChecklistItem = item => {
  editingItemId.value = item.id;
  currentChecklistItem.value = item.text;
  checklistDueDate.value = item.due_date || '';
  checklistPriority.value = item.priority || 'none';
};

const handleDeleteChecklistItem = async itemId => {
  try {
    await KanbanAPI.deleteChecklistItem(props.item?.id, itemId);

    // Buscar checklists atualizadas
    await fetchChecklists();

    // Mostrar mensagem de sucesso
    emitter.emit('newToastMessage', {
      message: 'Item do checklist deletado com sucesso',
      action: { type: 'success' },
    });

  } catch (error) {
    console.error('Erro ao deletar item do checklist:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao deletar item do checklist',
      action: { type: 'error' },
    });
  }
};

const handleToggleChecklistItem = async item => {
  try {
    await KanbanAPI.toggleChecklistItem(props.item?.id, item.id);

    // Buscar checklists atualizadas
    await fetchChecklists();

  } catch (error) {
    console.error('Erro ao atualizar item do checklist:', error);
  }
};

const cancelEditItem = () => {
  editingItemId.value = null;
  currentChecklistItem.value = '';
  checklistDueDate.value = '';
  checklistPriority.value = 'none';
};







// Computed para filtrar lista de agentes
const filteredAgentList = computed(() => {
  if (!agentSearch.value) return props.agentList;
  return props.agentList.filter(agent =>
    (agent.name || '').toLowerCase().includes(agentSearch.value.toLowerCase())
  );
});




// Função para buscar checklists do item
const fetchChecklists = async () => {
  try {
    loadingChecklists.value = true;
    const response = await KanbanAPI.getChecklists(props.item.id);
    internalChecklists.value = Array.isArray(response.data.checklist) ? response.data.checklist : [];
  } catch (error) {
    console.error('Erro ao buscar checklists:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao carregar checklists',
      action: { type: 'error' },
    });
  } finally {
    loadingChecklists.value = false;
  }
};

// Funções para gerenciar agentes dos itens do checklist
const assignAgentToChecklistItem = async (checklistItem, agentId) => {
  try {
    await KanbanAPI.assignAgentToChecklistItem(props.item?.id, checklistItem.id, agentId);
    // Recarregar checklists após atribuição
    await fetchChecklists();
  } catch (error) {
    console.error('Erro ao atribuir agente ao item do checklist:', error);
  }
};

const removeAgentFromChecklistItem = async checklistItem => {
  try {
    await KanbanAPI.removeAgentFromChecklistItem(props.item?.id, checklistItem.id);
    // Recarregar checklists após remoção
    await fetchChecklists();
  } catch (error) {
    console.error('Erro ao remover agente do item do checklist:', error);
  }
};

// Função para abrir modal de atribuição de agente para item do checklist
const openAgentAssignModalForChecklistItem = checklistItem => {
  selectedChecklistItemForAgent.value = checklistItem;
  showAgentAssignModal.value = true;
};

// Função para fechar modal de atribuição de agente
const closeAgentAssignModal = () => {
  showAgentAssignModal.value = false;
  selectedChecklistItemForAgent.value = null;
  selectedAgentId.value = null;
  agentSearch.value = '';
  agentAssignLoading.value = false;
};

// Função para abrir modal de detalhes do item
const openItemDetailsModal = checklistItem => {
  selectedChecklistItemDetails.value = checklistItem;
  showItemDetailsModal.value = true;
};

// Função para fechar modal de detalhes do item
const closeItemDetailsModal = () => {
  showItemDetailsModal.value = false;
  selectedChecklistItemDetails.value = null;
};

// Função para atribuir agente via modal
const assignAgentFromModal = async () => {
  if (!selectedAgentId.value || agentAssignLoading.value) return;
  if (!selectedChecklistItemForAgent.value) return;

  agentAssignLoading.value = true;
  try {
    await assignAgentToChecklistItem(
      selectedChecklistItemForAgent.value,
      selectedAgentId.value
    );
    closeAgentAssignModal();
    await fetchChecklists(); // Recarregar checklists após atribuição
    emitter.emit('newToastMessage', {
      message: 'Agente atribuído com sucesso ao item do checklist',
      type: 'success',
    });
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: 'Erro ao atribuir agente ao item do checklist',
      type: 'error',
    });
  } finally {
    agentAssignLoading.value = false;
  }
};

// Carregar checklists quando o componente for montado
onMounted(() => {
  if (props.item?.id) {
    fetchChecklists();
  }
});

// Função para alternar ordenação do checklist
const toggleChecklistSortOrder = () => {
  const sortOptions = ['newest', 'oldest'];
  const currentIndex = sortOptions.indexOf(checklistSortOrder.value);
  const nextIndex = (currentIndex + 1) % sortOptions.length;
  checklistSortOrder.value = sortOptions[nextIndex];
};

// Função para obter o texto da ordenação atual do checklist
const getChecklistSortOrderText = () => {
  switch (checklistSortOrder.value) {
    case 'newest':
      return 'Mais recentes';
    case 'oldest':
      return 'Mais antigas';
    default:
      return 'Mais recentes';
  }
};
</script>

<template>
  <div class="space-y-4">
    <!-- Header com estatísticas -->
    <div class="checklist-header">
      <div class="flex items-center justify-between">
        <div class="checklist-stats">
          <div class="flex items-center gap-4">
            <h3 class="text-lg font-semibold text-slate-900 dark:text-slate-100 whitespace-nowrap flex items-center gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-loader-icon lucide-loader text-slate-600 dark:text-slate-400">
                <path d="M12 2v4"/>
                <path d="m16.2 7.8 2.9-2.9"/>
                <path d="M18 12h4"/>
                <path d="m16.2 16.2 2.9 2.9"/>
                <path d="M12 18v4"/>
                <path d="m4.9 19.1 2.9-2.9"/>
                <path d="M2 12h4"/>
                <path d="m4.9 4.9 2.9 2.9"/>
              </svg>
              {{ t('KANBAN.FORM.CHECKLIST.TITLE') }}
            </h3>
            <div class="flex items-center gap-2 flex-1">
              <div class="progress-bar flex-1">
                <div
                  class="progress-fill"
                  :style="{ width: `${checklistStats.percentage}%` }"
                />
              </div>
              <span class="text-sm text-slate-600 dark:text-slate-400 whitespace-nowrap">
                {{ checklistStats.completed }}/{{ checklistStats.total }}
                {{ checklistStats.percentage }}%
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Campo de texto para novo item -->
    <div class="checklist-input-section">
      <Editor
        v-model="currentChecklistItem"
        :placeholder="t('KANBAN.FORM.CHECKLIST.PLACEHOLDER')"
        :max-length="1000"
        :show-character-count="true"
        :enable-variables="false"
        :enable-canned-responses="false"
        :enable-captain-tools="false"
        :enabled-menu-options="[]"
      />

      <!-- Campos de prazo e prioridade lado a lado -->
      <div class="flex items-start gap-4 mt-2">
        <!-- Campo de prazo -->
        <div class="flex-1">
          <label class="block text-sm text-slate-600 dark:text-slate-400 mb-1">
            <fluent-icon icon="calendar-clock" size="14" class="inline mr-1" />
            {{ t('KANBAN.FORM.CHECKLIST.DUE_DATE') }}
          </label>
          <input
            v-model="checklistDueDate"
            type="datetime-local"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-lg focus:ring-1 focus:ring-woot-500 focus:border-woot-500 dark:bg-slate-800 dark:border-slate-700 dark:text-slate-300"
            :min="new Date().toISOString().slice(0, 16)"
          />
        </div>

        <!-- Campo de prioridade -->
        <div class="flex-1">
          <label class="block text-sm text-slate-600 dark:text-slate-400 mb-1">
            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="inline mr-1 text-slate-600 dark:text-slate-400">
              <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>
            </svg>
            {{ t('KANBAN.FORM.CHECKLIST.PRIORITY') }}
          </label>
          <select
            v-model="checklistPriority"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-lg focus:ring-1 focus:ring-woot-500 focus:border-woot-500 dark:bg-slate-800 dark:border-slate-700 dark:text-slate-300"
          >
            <option value="none">Nenhuma</option>
            <option value="low">Baixa</option>
            <option value="medium">Média</option>
            <option value="high">Alta</option>
            <option value="urgent">Urgente</option>
          </select>
        </div>
      </div>

      <!-- Botões de ação -->
      <div class="flex items-center justify-end mt-2">
        <div class="flex items-center gap-2">
          <button
            v-if="editingItemId"
            class="secondary-button"
            @click="cancelEditItem"
          >
            <fluent-icon icon="dismiss" size="16" />
            <span class="ml-1">Cancelar</span>
          </button>
          <button
            class="primary-button"
            :class="{ 'primary-button-wide': editingItemId }"
            :disabled="!currentChecklistItem.trim()"
            @click="editingItemId ? handleUpdateChecklistItem() : handleAddChecklistItem()"
          >
            <fluent-icon :icon="editingItemId ? 'save' : 'add'" size="16" />
            <span v-if="editingItemId" class="ml-1">Salvar</span>
          </button>
        </div>
      </div>

    </div>



    <!-- Modal de atribuição de agente para item do checklist -->
    <Modal
      v-model:show="showAgentAssignModal"
      :on-close="closeAgentAssignModal"
      :show-close-button="true"
      size="medium"
    >
      <div
        class="p-4 bg-white dark:bg-slate-900 rounded-md border border-slate-100 dark:border-slate-800 shadow-lg"
      >
        <h3 class="text-lg font-medium mb-4">Gerenciar Agentes Atribuídos</h3>
        <p class="text-sm text-slate-600 dark:text-slate-400 mb-4">
          {{ selectedChecklistItemForAgent?.text }}
        </p>

        <!-- Seção de agentes já atribuídos -->
        <div v-if="selectedChecklistItemForAgent && getChecklistItemAgent(selectedChecklistItemForAgent)" class="mb-4">
          <h4 class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">
            Agente Atribuído
          </h4>
          <div class="space-y-2">
            <div class="flex items-center justify-between p-2 bg-slate-50 dark:bg-slate-800 rounded-md">
              <div class="flex items-center gap-2">
                <Avatar
                  :name="getChecklistItemAgent(selectedChecklistItemForAgent)?.name"
                  :src="getChecklistItemAgent(selectedChecklistItemForAgent)?.avatar_url || ''"
                  :size="24"
                />
                <div>
                  <div class="text-sm font-medium text-slate-900 dark:text-slate-100">
                    {{ getChecklistItemAgent(selectedChecklistItemForAgent)?.name }}
                  </div>
                </div>
              </div>
              <button
                class="p-1 text-slate-400 hover:text-red-500 transition-colors"
                @click="removeAgentFromChecklistItem(selectedChecklistItemForAgent)"
              >
                <fluent-icon icon="delete" size="16" />
              </button>
            </div>
          </div>
        </div>

        <!-- Seção para adicionar novo agente -->
        <div class="border-t border-slate-200 dark:border-slate-700 pt-4">
          <h4 class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">
            {{ selectedChecklistItemForAgent && getChecklistItemAgent(selectedChecklistItemForAgent) ? 'Alterar Agente' : 'Adicionar Novo Agente' }}
          </h4>
          <input
            v-model="agentSearch"
            type="text"
            class="w-full mb-3 px-3 py-2 border border-slate-100 dark:border-slate-800 rounded-md text-xs bg-white dark:bg-slate-800 focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
            placeholder="Buscar agentes..."
          />
          <div class="space-y-2 mb-4 max-h-40 overflow-y-auto">
            <button
              v-for="agent in filteredAgentList"
              :key="agent.id"
              type="button"
              class="flex items-center w-full px-3 py-1.5 rounded-md transition-colors gap-2 border border-slate-100 dark:border-slate-800 text-xs font-normal hover:bg-slate-100 dark:hover:bg-slate-800"
              :class="[
                selectedAgentId === agent.id
                  ? 'border-woot-500 bg-woot-50 dark:bg-woot-900/30 font-bold text-woot-600'
                  : '',
                getChecklistItemAgent(selectedChecklistItemForAgent)?.id === agent.id
                  ? 'opacity-50 cursor-not-allowed'
                  : '',
              ]"
              :disabled="getChecklistItemAgent(selectedChecklistItemForAgent)?.id === agent.id"
              @click="selectedAgentId = agent.id"
            >
              <Avatar
                :name="agent.name || 'Agente'"
                :src="agent.avatar_url || ''"
                :size="24"
                class="mr-2"
              />
              <span class="truncate">{{ agent.name || 'Agente' }}</span>
              <span
                v-if="getChecklistItemAgent(selectedChecklistItemForAgent)?.id === agent.id"
                class="ml-auto text-slate-400 text-xs"
                >Já atribuído</span
              >
              <span
                v-else-if="selectedAgentId === agent.id"
                class="ml-auto text-woot-500 text-xs font-semibold"
                >Selecionado</span
              >
            </button>
            <div
              v-if="filteredAgentList.length === 0"
              class="px-3 py-2 text-slate-400 text-xs"
            >
              Nenhum agente encontrado
            </div>
          </div>
        </div>

        <div class="flex justify-end gap-2 mt-4">
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            @click="closeAgentAssignModal"
            >Fechar</Button
          >
          <Button
            variant="solid"
            color="blue"
            size="sm"
            :isLoading="agentAssignLoading"
            :disabled="
              !selectedAgentId ||
              agentAssignLoading ||
              getChecklistItemAgent(selectedChecklistItemForAgent)?.id === selectedAgentId
            "
            @click="assignAgentFromModal"
            >{{ selectedChecklistItemForAgent && getChecklistItemAgent(selectedChecklistItemForAgent) ? 'Alterar Agente' : 'Adicionar Agente' }}</Button
          >
        </div>
      </div>
    </Modal>

    <!-- Modal de detalhes do item do checklist -->
    <Modal
      v-model:show="showItemDetailsModal"
      :on-close="closeItemDetailsModal"
      :show-close-button="true"
      size="large"
    >
      <div
        v-if="selectedChecklistItemDetails"
        class="p-6 bg-white dark:bg-slate-900 rounded-md border border-slate-100 dark:border-slate-800 max-h-[80vh] overflow-y-auto"
      >
        <!-- Header do modal -->
        <div class="flex items-start justify-between mb-6">
          <div class="flex items-center gap-3">
            <!-- Título do item -->
            <div class="flex-1">
              <div class="flex items-center gap-3">
                <h2 class="text-xl font-semibold text-slate-900 dark:text-slate-100">
                  Detalhes do Item #{{ selectedChecklistItemDetails.id }}
                </h2>

                <!-- Status do item -->
                <div class="flex items-center gap-2">
                  <button
                    class="w-6 h-6 rounded border-2 flex items-center justify-center transition-all"
                    :class="{
                      'bg-green-500 border-green-500 text-white': selectedChecklistItemDetails.completed,
                      'border-slate-300 dark:border-slate-600': !selectedChecklistItemDetails.completed
                    }"
                  >
                    <fluent-icon
                      v-if="selectedChecklistItemDetails.completed"
                      icon="checkmark"
                      size="14"
                      class="text-white"
                    />
                  </button>
                  <span class="text-sm font-medium px-2 py-1 rounded-full"
                        :class="{
                          'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300': selectedChecklistItemDetails.completed,
                          'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-300': !selectedChecklistItemDetails.completed
                        }">
                    {{ selectedChecklistItemDetails.completed ? 'Concluído' : 'Pendente' }}
                  </span>
                </div>
              </div>
              <p class="text-sm text-slate-500 dark:text-slate-400 mt-1">
                Item do checklist
              </p>
            </div>
          </div>
        </div>

        <!-- Conteúdo principal -->
        <div class="space-y-6">
          <!-- Datas de criação e atualização -->
          <div class="flex items-center gap-6 text-sm text-slate-600 dark:text-slate-400">
            <div class="flex items-center gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-slate-500 dark:text-slate-500">
                <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/>
                <line x1="16" y1="2" x2="16" y2="6"/>
                <line x1="8" y1="2" x2="8" y2="6"/>
                <line x1="3" y1="10" x2="21" y2="10"/>
                <line x1="12" y1="14" x2="12" y2="18"/>
                <line x1="9" y1="16" x2="15" y2="16"/>
              </svg>
              <span class="font-medium">Criado em:</span>
              <span class="text-slate-700 dark:text-slate-300">{{ formatDate(selectedChecklistItemDetails.created_at) }}</span>
            </div>

            <div v-if="selectedChecklistItemDetails.updated_at" class="flex items-center gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-slate-500 dark:text-slate-500">
                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
              </svg>
              <span class="font-medium">Atualizado em:</span>
              <span class="text-slate-700 dark:text-slate-300">{{ formatDate(selectedChecklistItemDetails.updated_at) }}</span>
            </div>

            <div v-if="selectedChecklistItemDetails.due_date" class="flex items-center gap-2">
              <fluent-icon icon="calendar-clock" size="16" class="text-slate-500 dark:text-slate-500" />
              <span class="font-medium">{{ t('KANBAN.FORM.CHECKLIST.DUE_DATE') }}</span>
              <span class="text-slate-700 dark:text-slate-300">{{ formatDate(selectedChecklistItemDetails.due_date) }}</span>
            </div>
          </div>

          <!-- Texto do item -->
          <div>
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">
              Descrição
            </label>
            <div
              class="prose prose-sm max-w-none p-4 bg-slate-50 dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700"
              v-html="renderMarkdown(selectedChecklistItemDetails.text)"
            ></div>
          </div>

          <!-- Prioridade -->
          <div v-if="getChecklistItemPriority(selectedChecklistItemDetails).label !== 'Nenhuma'">
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">
              Prioridade
            </label>
            <div class="p-3 bg-slate-50 dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700">
              <span
                class="inline-flex items-center gap-2 px-3 py-1 text-sm font-medium rounded-full"
                :class="{
                  'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300': getChecklistItemPriority(selectedChecklistItemDetails).color === 'red',
                  'bg-orange-100 dark:bg-orange-900/30 text-orange-700 dark:text-orange-300': getChecklistItemPriority(selectedChecklistItemDetails).color === 'orange',
                  'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-300': getChecklistItemPriority(selectedChecklistItemDetails).color === 'yellow',
                  'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300': getChecklistItemPriority(selectedChecklistItemDetails).color === 'green',
                }"
              >
                <svg
                  v-if="getChecklistItemPriority(selectedChecklistItemDetails).iconSvg"
                  xmlns="http://www.w3.org/2000/svg"
                  width="16"
                  height="16"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  v-html="getChecklistItemPriority(selectedChecklistItemDetails).iconSvg"
                  class="flex-shrink-0"
                ></svg>
                {{ getChecklistItemPriority(selectedChecklistItemDetails).label }}
              </span>
            </div>
          </div>

          <!-- Autor do item -->
          <div v-if="getChecklistItemAuthor(selectedChecklistItemDetails)">
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">
              Autor
            </label>
            <div class="flex items-center gap-3 p-3 bg-slate-50 dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700">
              <Avatar
                :name="getChecklistItemAuthor(selectedChecklistItemDetails).name"
                :src="getChecklistItemAuthor(selectedChecklistItemDetails).avatar_url"
                :size="32"
              />
              <div>
                <div class="text-sm font-medium text-slate-900 dark:text-slate-100">
                  {{ getChecklistItemAuthor(selectedChecklistItemDetails).name }}
                </div>
                <div class="text-xs text-slate-500 dark:text-slate-400">
                  Criado por
                </div>
              </div>
            </div>
          </div>

          <!-- Agente responsável -->
          <div v-if="getChecklistItemAgent(selectedChecklistItemDetails)">
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">
              Responsável
            </label>
            <div class="flex items-center gap-3 p-3 bg-slate-50 dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700">
              <Avatar
                :name="getChecklistItemAgent(selectedChecklistItemDetails).name"
                :src="getChecklistItemAgent(selectedChecklistItemDetails).avatar_url"
                :size="32"
              />
              <div>
                <div class="text-sm font-medium text-slate-900 dark:text-slate-100">
                  {{ getChecklistItemAgent(selectedChecklistItemDetails).name }}
                </div>
                <div class="text-xs text-slate-500 dark:text-slate-400">
                  Agente responsável
                </div>
              </div>
            </div>
          </div>



        </div>

      </div>
    </Modal>

    <!-- Botão de ordenação acima da listagem -->
    <div class="flex justify-end items-center mb-4">
      <button
        v-if="displayChecklists.length > 1"
        class="checklist-sort-button"
        @click="toggleChecklistSortOrder"
        :title="getChecklistSortOrderText()"
      >
        <fluent-icon icon="arrow-sort" size="16" />
        <span class="ml-1">{{ getChecklistSortOrderText() }}</span>
      </button>
    </div>

    <!-- Seção de checklist -->
    <div class="checklist-section">
      <!-- Lista de itens do checklist -->
      <div class="space-y-2">
        <div
          v-for="checklistItem in filteredChecklistItems"
          :key="checklistItem.id"
          class="checklist-item group cursor-pointer"
          :class="{ 'completed': checklistItem.completed }"
          @click="openItemDetailsModal(checklistItem)"
        >
          <div class="flex items-start gap-3">
            <!-- Checkbox -->
            <div class="flex-shrink-0 mt-1">
              <button
                class="checklist-checkbox"
                :class="{ 'checked': checklistItem.completed }"
                @click.stop="handleToggleChecklistItem(checklistItem)"
              >
                <fluent-icon
                  v-if="checklistItem.completed"
                  icon="checkmark"
                  size="12"
                  class="text-white"
                />
              </button>
            </div>

            <!-- Conteúdo do item -->
            <div class="flex-1 min-w-0">
              <div class="flex items-start justify-between gap-2">
                <div class="checklist-text" v-html="renderMarkdown(checklistItem.text)">
                </div>

                <!-- Botões de ação -->
                <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    class="p-1 text-slate-400 hover:text-slate-600 dark:hover:text-slate-300"
                    @click.stop="handleEditChecklistItem(checklistItem)"
                  >
                    <fluent-icon icon="edit" size="14" />
                  </button>
                  <button
                    class="p-1 text-slate-400 hover:text-n-ruby-9 dark:hover:text-n-ruby-4"
                    @click.stop="handleDeleteChecklistItem(checklistItem.id)"
                  >
                    <fluent-icon icon="delete" size="14" />
                  </button>
                </div>
              </div>


              <!-- Metadados do item -->
              <div class="checklist-metadata mt-2 w-full">
                <div class="flex items-center justify-between w-full">
                  <div class="flex items-center gap-2">
                    <!-- Prioridade -->
                    <div v-if="getChecklistItemPriority(checklistItem).label !== 'Nenhuma'" class="checklist-priority">
                      <span
                        class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-full"
                        :class="{
                          'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300': getChecklistItemPriority(checklistItem).color === 'red',
                          'bg-orange-100 dark:bg-orange-900/30 text-orange-700 dark:text-orange-300': getChecklistItemPriority(checklistItem).color === 'orange',
                          'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-300': getChecklistItemPriority(checklistItem).color === 'yellow',
                          'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300': getChecklistItemPriority(checklistItem).color === 'green',
                        }"
                      >
                        <svg
                          v-if="getChecklistItemPriority(checklistItem).iconSvg"
                          xmlns="http://www.w3.org/2000/svg"
                          width="10"
                          height="10"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          stroke-width="2"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          v-html="getChecklistItemPriority(checklistItem).iconSvg"
                          class="flex-shrink-0"
                        ></svg>
                        {{ getChecklistItemPriority(checklistItem).label }}
                      </span>
                    </div>

                    <Avatar
                      v-if="getChecklistItemAuthor(checklistItem)"
                      :name="getChecklistItemAuthor(checklistItem).name"
                      :src="getChecklistItemAuthor(checklistItem).avatar_url"
                      :size="16"
                    />
                    <span class="checklist-author text-xs">
                      {{ getChecklistItemAuthor(checklistItem)?.name || 'Sem autor' }}
                    </span>

                    <!-- Botão para atribuir agente -->
                    <button
                      v-if="isStacklab"
                      class="flex items-center gap-1 px-2 py-1 text-xs text-slate-500 hover:text-slate-700 bg-slate-50 hover:bg-slate-100 dark:text-slate-400 dark:hover:text-slate-300 dark:bg-slate-800 dark:hover:bg-slate-700 rounded transition-colors"
                      @click.stop="openAgentAssignModalForChecklistItem(checklistItem)"
                    >
                      <fluent-icon icon="person-add" size="12" />
                      <span v-if="getChecklistItemAgent(checklistItem)">Alterar agente</span>
                      <span v-else>Atribuir agente</span>
                    </button>
                  </div>

                  <span class="checklist-date text-xs text-slate-400">
                    {{ formatDate(checklistItem.created_at || new Date()) }}
                  </span>
                </div>
              </div>

              <!-- Prazo do item -->
              <div v-if="checklistItem.due_date" class="checklist-due-date-container mt-2">
                <span
                  class="checklist-due-date text-sm font-medium flex items-center gap-2 px-2 py-1 rounded-md border"
                  :class="{
                    'text-red-700 dark:text-red-300 bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800': new Date(checklistItem.due_date) < new Date() && !checklistItem.completed,
                    'text-yellow-700 dark:text-yellow-300 bg-yellow-50 dark:bg-yellow-900/20 border-yellow-200 dark:border-yellow-800': new Date(checklistItem.due_date) >= new Date() && new Date(checklistItem.due_date) <= new Date(Date.now() + 24 * 60 * 60 * 1000) && !checklistItem.completed,
                    'text-slate-600 dark:text-slate-400 bg-slate-50 dark:bg-slate-800/50 border-slate-200 dark:border-slate-700': new Date(checklistItem.due_date) > new Date(Date.now() + 24 * 60 * 60 * 1000) || checklistItem.completed
                  }"
                >
                  <fluent-icon icon="calendar-clock" size="14" />
                  {{ t('KANBAN.FORM.CHECKLIST.DUE_DATE') }} {{ formatDate(checklistItem.due_date) }}
                </span>
              </div>

            </div>

          </div>
        </div>
      </div>

      <!-- Mensagem quando não há itens -->
      <div
        v-if="displayChecklists.length === 0"
        class="text-center py-8 text-slate-500"
      >
        <fluent-icon icon="list" size="48" class="mx-auto mb-4 opacity-50" />
        <p class="text-sm">{{ t('KANBAN.FORM.CHECKLIST.EMPTY') }}</p>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Estilos específicos do componente ChecklistTab */
.checklist-header {
  @apply bg-white dark:bg-slate-800 rounded-lg p-4 border border-slate-200 dark:border-slate-700;
}

.checklist-stats {
  @apply flex-1;
}

.progress-bar {
  @apply flex-1 h-2 bg-slate-200 dark:bg-slate-700 rounded-full overflow-hidden;
}

.progress-fill {
  @apply h-full bg-green-500 transition-all duration-300 ease-out;
}

.checklist-input-section {
  @apply space-y-2;
}


.primary-button {
  @apply flex items-center justify-center w-10 h-10 text-sm font-medium text-white
         bg-woot-500 hover:bg-woot-600
         dark:bg-woot-600 dark:hover:bg-woot-700
         rounded-lg transition-colors;

  &:disabled {
    @apply opacity-50 cursor-not-allowed;
  }
}

.primary-button-wide {
  @apply w-auto px-4 min-w-[80px];
}

.secondary-button {
  @apply flex items-center justify-center px-3 py-2 text-sm font-medium
         text-slate-600 dark:text-slate-400
         bg-slate-100 hover:bg-slate-200
         dark:bg-slate-700 dark:hover:bg-slate-600
         rounded-lg transition-colors;

  &:disabled {
    @apply opacity-50 cursor-not-allowed;
  }
}

.checklist-section {
  @apply space-y-2;
}

.checklist-item {
  @apply bg-white dark:bg-slate-800 rounded-lg p-4 border border-slate-200 dark:border-slate-700
         hover:border-slate-300 dark:hover:border-slate-600 transition-all duration-200;

  &.completed {
    @apply opacity-75;
  }

  &.completed .checklist-text {
    @apply line-through text-slate-500 dark:text-slate-400;
  }
}


.checklist-checkbox {
  @apply w-5 h-5 rounded bg-white dark:bg-slate-700 flex items-center justify-center
         hover:border-woot-500 transition-all duration-200;
  border: 1px solid #9ca3af;

  &.checked {
    @apply bg-green-500 border-green-500;
    border-color: #10b981;
  }
}

.checklist-text {
  @apply flex-1 text-slate-700 dark:text-slate-300 text-sm leading-relaxed
         break-words overflow-hidden;

  /* Estilos para markdown renderizado */
  :deep(p) {
    @apply mb-2 last:mb-0;
  }

  :deep(ul), :deep(ol) {
    @apply ml-4 mb-2;
  }

  :deep(li) {
    @apply mb-1;
  }

  :deep(strong), :deep(b) {
    @apply font-semibold;
  }

  :deep(em), :deep(i) {
    @apply italic;
  }

  :deep(code) {
    @apply bg-slate-100 dark:bg-slate-800 px-1 py-0.5 rounded text-xs font-mono;
  }

  :deep(pre) {
    @apply bg-slate-100 dark:bg-slate-800 p-2 rounded text-xs font-mono overflow-x-auto mb-2;
  }

  :deep(a) {
    @apply text-woot-500 dark:text-woot-400 hover:underline;
  }

  :deep(blockquote) {
    @apply border-l-4 border-slate-300 dark:border-slate-600 pl-4 italic text-slate-600 dark:text-slate-400;
  }
}

.checklist-metadata {
  @apply flex items-center gap-2 text-xs text-slate-500 dark:text-slate-400;
}

.checklist-author {
  @apply font-medium;
}

.checklist-priority {
  @apply flex-shrink-0;
}



/* Responsividade */
@media (max-width: 640px) {
  .checklist-item {
    @apply p-3;
  }

}


/* Scrollbar customizado */
.custom-scrollbar {
  scrollbar-width: thin;
  scrollbar-color: var(--color-scrollbar) transparent;
}

.custom-scrollbar::-webkit-scrollbar {
  width: 6px;
}

.custom-scrollbar::-webkit-scrollbar-track {
  background: transparent;
}

.custom-scrollbar::-webkit-scrollbar-thumb {
  background-color: var(--color-scrollbar);
  border-radius: 3px;
}

.dark .custom-scrollbar {
  scrollbar-color: var(--color-scrollbar-dark) transparent;
}

.dark .custom-scrollbar::-webkit-scrollbar-thumb {
  background-color: var(--color-scrollbar-dark);
}

/* Botão de ordenação do checklist */
.checklist-sort-button {
  @apply flex items-center px-3 py-1.5 text-sm font-medium
         text-slate-600 dark:text-slate-400
         bg-slate-100 hover:bg-slate-200
         dark:bg-slate-700 dark:hover:bg-slate-600
         rounded-lg transition-colors duration-200
         border border-slate-200 dark:border-slate-600;
}

.checklist-sort-button:hover {
  @apply text-slate-900 dark:text-slate-200;
}
</style>
