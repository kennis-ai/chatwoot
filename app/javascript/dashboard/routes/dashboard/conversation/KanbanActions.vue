<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import FunnelAPI from '../../../api/funnel';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});
const emit = defineEmits([]);
const { t } = useI18n();
import agents from '../../../api/agents';
import KanbanItemForm from '../kanban/components/KanbanItemForm.vue';
import Modal from '../../../components/Modal.vue';
import { format, formatDistanceToNow } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import KanbanItemDetails from '../kanban/components/KanbanItemDetails.vue';
import { emitter } from 'shared/helpers/mitt';
import Button from '../../../components-next/button/Button.vue';
import MarkdownIt from 'markdown-it';
import Avatar from '../../../components-next/avatar/Avatar.vue';
import KanbanAPI from '../../../api/kanban';

// Instância do MarkdownIt com configurações padrão
const md = new MarkdownIt({
  html: false, // Desabilitar HTML inline para segurança
  breaks: true, // Converter quebras de linha em <br>
  linkify: true, // Converter URLs em links automaticamente
});

// Função para renderizar markdown
const renderMarkdown = text => {
  if (!text) return '';

  // Renderizar diretamente - markdown-it já suporta listas por padrão
  return md.render(text);
};

const store = useStore();
const funnels = ref([]);
const showKanbanForm = ref(false);
const previewData = ref(null);

// Adicione estas refs para controlar o modal de detalhes
const showDetailsModal = ref(false);
const itemToShow = ref(null);

// Adicionar ref para agentsList
const agentsList = ref([]);

// Refs para checklist
const internalChecklists = ref([]);
const loadingChecklists = ref(false);

// Computed para trabalhar com múltiplos agentes
const agentInfo = computed(() => {
  console.log('[KanbanActions] Computing agentInfo:', {
    kanbanItemComputed: kanbanItemComputed.value,
    assigned_agents: kanbanItemComputed.value?.assigned_agents,
    length: kanbanItemComputed.value?.assigned_agents?.length,
  });

  // Verificar se há agentes atribuídos
  if (
    kanbanItemComputed.value?.assigned_agents &&
    kanbanItemComputed.value.assigned_agents.length > 0
  ) {
    const mappedAgents = kanbanItemComputed.value.assigned_agents.map(
      agent => ({
        id: agent.id,
        name: agent.name,
        avatar_url: agent.avatar_url || '',
        assigned_at: agent.assigned_at,
        assigned_by: agent.assigned_by,
      })
    );

    console.log('[KanbanActions] Mapped agents:', mappedAgents);
    return mappedAgents;
  }

  console.log('[KanbanActions] No assigned agents found');
  return [];
});

// Computed para o agente principal (primeiro da lista)
const primaryAgent = computed(() => {
  const result = agentInfo.value.length > 0 ? agentInfo.value[0] : null;
  console.log('[KanbanActions] Primary agent:', result);
  return result;
});

// Modal de atribuição rápida de agente
const showAgentAssignModal = ref(false);
const agentAssignLoading = ref(false);
const selectedAgentId = ref(null);
const agentSearch = ref('');

// Modal de mover funil
const showMoveFunnelModal = ref(false);
const availableFunnels = ref([]);
const selectedFunnelId = ref(null);
const selectedStage = ref(null);
const isMovingItem = ref(false);

// Obtém os dados do contato e conversa atual
const currentChat = computed(() => store.getters.getSelectedChat);
const contactName = computed(
  () => currentChat.value?.meta?.sender?.name || 'Sem nome'
);

// Obtém o item do kanban diretamente da conversa
const kanbanItemComputed = computed(() => {
  if (
    !currentChat.value?.kanban_items ||
    currentChat.value.kanban_items.length === 0
  )
    return null;
  return currentChat.value.kanban_items[0]; // Pega o primeiro item do kanban
});

// Formata a conversa atual para o select
const currentConversation = computed(() => {
  if (!currentChat.value) return null;

  return {
    id: currentChat.value.id,
    meta: currentChat.value.meta,
    messages: currentChat.value.messages || [],
  };
});

// Watch para mudanças no conversationId
watch(
  () => props.conversationId,
  async (newId, oldId) => {
    console.log('[KanbanActions] Conversation ID changed:', {
      newId,
      oldId,
      currentChat: currentChat.value,
    });
    if (newId && newId !== oldId) {
      // Não precisamos mais buscar o item do kanban via API
      // Os dados vêm diretamente da conversa
      console.log(
        '[KanbanActions] New kanban item data:',
        kanbanItemComputed.value
      );
      // Buscar checklists quando a conversa mudar
      await fetchChecklists();
    }
  }
);

const currentFunnel = computed(() => {
  const item = previewData.value || kanbanItemComputed.value;
  if (!item?.funnel) return null;
  return item.funnel; // Usar o funil que vem diretamente do item
});

const kanbanStageLabel = computed(() => {
  const item = previewData.value || kanbanItemComputed.value;
  if (!item || !currentFunnel.value?.stages) return null;
  const stage = currentFunnel.value.stages[item.funnel_stage];
  return stage?.name || item.funnel_stage;
});

const stageStyle = computed(() => {
  const item = previewData.value || kanbanItemComputed.value;
  if (!item || !currentFunnel.value?.stages) return {};
  const stage = currentFunnel.value.stages[item.funnel_stage];
  if (!stage?.color) return {};
  return {
    backgroundColor: `${stage.color}20`,
    color: stage.color,
  };
});

const funnelStyle = computed(() => ({
  backgroundColor: '#64748B20',
  color: '#64748B',
}));

// Dados iniciais para o formulário do Kanban
const initialFormData = computed(() => {
  if (kanbanItemComputed.value) {
    // Se já existe um item, preservar todos os dados existentes
    return {
      ...kanbanItemComputed.value,
      description: kanbanItemComputed.value.item_details?.description || '',
      item_details: {
        ...kanbanItemComputed.value.item_details,
        description: kanbanItemComputed.value.item_details?.description || '',
        _agent: kanbanItemComputed.value.item_details?.agent_id
          ? agentsList.value.find(
              a => a.id === kanbanItemComputed.value.item_details.agent_id
            )
          : null,
      },
      _conversation: currentConversation.value,
    };
  }

  // Se é um novo item, usar os dados da conversa atual
  const assignedAgent = currentChat.value?.meta?.assignee;
  const priority = currentChat.value?.priority || 'none';

  return {
    title: contactName.value,
    description: '',
    funnel_id: funnels.value[0]?.id,
    funnel_stage: 'lead',
    item_details: {
      title: contactName.value,
      description: '',
      conversation_id: props.conversationId,
      agent_id: assignedAgent?.id || null,
      _agent: assignedAgent,
      priority: priority,
    },
    _conversation: currentConversation.value,
  };
});

const fetchFunnels = async () => {
  try {
    const response = await FunnelAPI.get();
    funnels.value = response.data;
  } catch (error) {}
};

// Modificar onMounted para incluir carregamento de agentes
onMounted(async () => {
  console.log('[KanbanActions] Component mounted, fetching data...');
  await Promise.all([fetchFunnels(), fetchAgents()]);
  console.log(
    '[KanbanActions] Data fetched, kanbanItemComputed:',
    kanbanItemComputed.value
  );
  // Buscar checklists se houver item do kanban
  if (kanbanItemComputed.value?.id) {
    await fetchChecklists();
  }
});

const handleKanbanFormSave = async item => {
  try {
    showKanbanForm.value = false;
    previewData.value = null;

    // Emitir evento para atualizar o kanban
    emitter.emit('kanban.item.updated');

    // Emitir evento para atualizar a conversa se necessário
    if (currentChat.value) {
      emitter.emit('conversation.updated', currentChat.value.id);
    }
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: 'Erro ao salvar alterações',
      type: 'error',
    });
  }
};

// Adicionar função para carregar agentes
const fetchAgents = async () => {
  try {
    const { data } = await agents.get();
    agentsList.value = data;
  } catch (error) {
    // Tratar erro silenciosamente
  }
};

// Função para buscar checklists do item
const fetchChecklists = async () => {
  if (!kanbanItemComputed.value?.id) return;

  try {
    loadingChecklists.value = true;
    const response = await KanbanAPI.getChecklists(kanbanItemComputed.value.id);
    internalChecklists.value = Array.isArray(response.data.checklist)
      ? response.data.checklist
      : [];
  } catch (error) {
    console.error('Erro ao buscar checklists:', error);
  } finally {
    loadingChecklists.value = false;
  }
};

// Função para alternar estado do item do checklist
const handleToggleChecklistItem = async item => {
  if (!kanbanItemComputed.value?.id) return;

  try {
    await KanbanAPI.toggleChecklistItem(kanbanItemComputed.value.id, item.id);

    // Buscar checklists atualizadas
    await fetchChecklists();
  } catch (error) {
    console.error('Erro ao atualizar item do checklist:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao atualizar item do checklist',
      type: 'error',
    });
  }
};

// New computed properties
const priorityLabel = computed(() => {
  const priority = kanbanItemComputed.value?.item_details?.priority;
  const labels = {
    low: 'Baixa',
    medium: 'Média',
    high: 'Alta',
    urgent: 'Urgente',
    none: 'Nenhuma',
  };
  return labels[priority] || labels.none;
});

const priorityStyle = computed(() => {
  const priority = kanbanItemComputed.value?.item_details?.priority;
  const colors = {
    low: '#10B981',
    medium: '#F59E0B',
    high: '#EF4444',
    urgent: '#7C3AED',
    none: '#64748B',
  };
  const color = colors[priority] || colors.none;
  return {
    backgroundColor: `${color}20`,
    color: color,
  };
});

const hasScheduling = computed(() => {
  return !!(
    kanbanItemComputed.value?.item_details?.deadline_at ||
    kanbanItemComputed.value?.item_details?.scheduled_at
  );
});

const hasDetailsData = computed(() => {
  return !!(
    kanbanItemComputed.value?.item_details?.value ||
    (kanbanItemComputed.value?.item_details?.priority &&
      kanbanItemComputed.value?.item_details?.priority !== 'none') ||
    hasScheduling.value
  );
});

// New methods
const formatCurrency = (value, currency) => {
  if (!value) return '-';
  return new Intl.NumberFormat(currency?.locale || 'pt-BR', {
    style: 'currency',
    currency: currency?.code || 'BRL',
  }).format(value);
};

const formatDate = date => {
  if (!date) return '-';
  return format(new Date(date), 'dd/MM/yyyy', { locale: ptBR });
};

const formatDateTime = datetime => {
  if (!datetime) return '-';
  return format(new Date(datetime), "dd/MM/yyyy 'às' HH:mm", { locale: ptBR });
};

// Adicione esta função para formatar o tempo na etapa
const formatTimeInStage = date => {
  if (!date) return '';
  return formatDistanceToNow(new Date(date), {
    locale: ptBR,
    addSuffix: true,
  });
};

// Modifique a função handleShowDetails para usar o item completo
const handleShowDetails = item => {
  // Certifique-se de que o item tem todas as propriedades necessárias
  const formattedItem = {
    ...item,
    title: item.item_details?.title || contactName.value,
    description: item.item_details?.description || '',
    priority: item.item_details?.priority || 'none',
    funnel_stage: item.funnel_stage,
    item_details: {
      ...item.item_details,
      priority: item.item_details?.priority || 'none',
    },
  };

  itemToShow.value = formattedItem;
  showDetailsModal.value = true;
};

// Adicione esta função para atualizar os dados quando o modal for fechado
const handleDetailsUpdate = async () => {
  // Kanban item is no longer fetched here, so this function might need adjustment
  // if it's intended to refetch the item when the modal closes.
  // For now, it will just close the modal.
  showDetailsModal.value = false;
  itemToShow.value = null;
};

// Funções para modal de agentes
const openAgentAssignModal = () => {
  console.log('[KanbanActions] Opening agent assign modal:', {
    primaryAgent: primaryAgent.value,
    primaryAgentId: primaryAgent.value?.id,
    kanbanItemComputed: kanbanItemComputed.value,
    assigned_agents: kanbanItemComputed.value?.assigned_agents,
  });

  selectedAgentId.value = primaryAgent.value?.id || null;
  console.log('[KanbanActions] Set selectedAgentId to:', selectedAgentId.value);

  showAgentAssignModal.value = true;
};

const assignAgent = async () => {
  if (!selectedAgentId.value || agentAssignLoading.value) return;
  agentAssignLoading.value = true;
  try {
    // Atualizar o item do kanban com o novo agente
    const updatedItem = {
      ...kanbanItemComputed.value,
      item_details: {
        ...kanbanItemComputed.value.item_details,
        agent_id: selectedAgentId.value,
      },
    };

    // Emitir evento para atualizar o kanban
    emitter.emit('kanban.item.updated', updatedItem);

    showAgentAssignModal.value = false;
    selectedAgentId.value = null;
    emitter.emit('newToastMessage', {
      message: 'Agente atribuído com sucesso',
      type: 'success',
    });
  } catch (error) {
    console.error('Erro ao atribuir agente:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao atribuir agente',
      type: 'error',
    });
  } finally {
    agentAssignLoading.value = false;
  }
};

const removeAgent = async () => {
  try {
    const updatedItem = {
      ...kanbanItemComputed.value,
      item_details: {
        ...kanbanItemComputed.value.item_details,
        agent_id: null,
      },
    };

    emitter.emit('kanban.item.updated', updatedItem);
    showAgentAssignModal.value = false;
    emitter.emit('newToastMessage', {
      message: 'Agente removido com sucesso',
      type: 'success',
    });
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: 'Erro ao remover agente',
      type: 'error',
    });
  }
};

// Computed para lista filtrada de agentes
const filteredAgentList = computed(() => {
  if (!agentSearch.value) return agentsList.value;
  return agentsList.value.filter(agent =>
    (agent.name || '').toLowerCase().includes(agentSearch.value.toLowerCase())
  );
});

// Computed para checklists ordenados
const displayChecklists = computed(() => {
  let checklists = Array.isArray(internalChecklists.value)
    ? internalChecklists.value
    : [];
  if (!checklists || checklists.length === 0) return [];

  return [...checklists].sort((a, b) => {
    return new Date(b.created_at || 0) - new Date(a.created_at || 0);
  });
});

// Computed para estatísticas do checklist
const checklistStats = computed(() => {
  const checklists = displayChecklists.value;
  const total = checklists.length;
  const completed = checklists.filter(item => item.completed).length;
  const percentage = total > 0 ? Math.round((completed / total) * 100) : 0;
  return { total, completed, percentage };
});

// Computed para o funil selecionado no modal
const selectedFunnelForModal = computed(() => {
  return availableFunnels.value.find(f => f.id === selectedFunnelId.value);
});

// Funções auxiliares para o header do modal de detalhes
const getItemStatusInfo = item => {
  const status = item?.item_details?.status?.toLowerCase();

  const statusMap = {
    won: {
      label: 'Ganho',
      class: 'bg-green-50 dark:bg-green-900 text-green-700 dark:text-green-300',
    },
    lost: {
      label: 'Perdido',
      class: 'bg-red-50 dark:bg-red-900 text-red-700 dark:text-red-300',
    },
  };

  // Se não há status definido, retorna "Aberto" com cor neutra
  if (!status) {
    return {
      label: 'Aberto',
      class: 'bg-blue-50 dark:bg-blue-900 text-blue-700 dark:text-blue-300',
    };
  }

  return (
    statusMap[status] || {
      label: 'Aberto',
      class: 'bg-blue-50 dark:bg-blue-900 text-blue-700 dark:text-blue-300',
    }
  );
};

const getItemStatusClass = item => {
  return getItemStatusInfo(item).class;
};

const getItemStatusLabel = item => {
  return getItemStatusInfo(item).label;
};

const getPriorityInfo = item => {
  if (!item || !item.item_details?.priority) {
    return null;
  }
  const priority = item.item_details.priority.toLowerCase();
  if (priority === 'none') return null;

  const priorityMap = {
    high: {
      label: 'Alta',
      class: 'bg-n-ruby-3 dark:bg-n-ruby-8 text-n-ruby-9 dark:text-n-ruby-1',
    },
    medium: {
      label: 'Média',
      class:
        'bg-yellow-50 dark:bg-yellow-800 text-yellow-800 dark:text-yellow-50',
    },
    low: {
      label: 'Baixa',
      class: 'bg-green-50 dark:bg-green-800 text-green-800 dark:text-green-50',
    },
  };

  return priorityMap[priority] || null;
};

const getConversationCustomAttributes = item => {
  const conversation = item?.conversation;
  if (!conversation?.custom_attributes) return [];

  // Filtrar apenas atributos não vazios
  const filtered = [];
  Object.entries(conversation.custom_attributes).forEach(([key, value]) => {
    if (value !== null && value !== undefined && value !== '') {
      filtered.push({ key, value });
    }
  });

  return filtered;
};

const getFormattedUpdatedAt = item => {
  if (!item?.updated_at) return '';
  try {
    const date = new Date(item.updated_at);
    return date.toLocaleString('pt-BR', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch (error) {
    return '';
  }
};

const getFormattedDeadlineAt = item => {
  if (!item?.item_details?.deadline_at) return '';
  try {
    const date = new Date(item.item_details.deadline_at);
    return date.toLocaleDateString('pt-BR', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
  } catch (error) {
    return '';
  }
};

const getStatusInfo = item => {
  if (!item?.item_details?.status) {
    return null;
  }
  const status = item.item_details.status;
  if (status === 'won') {
    const closedOffer = item.item_details.closed_offer;
    let label = 'Ganho';

    if (closedOffer) {
      const currency = closedOffer.currency || item.item_details.currency;
      const value = closedOffer.value;
      const symbol = currency?.symbol || 'R$';
      const formattedValue = new Intl.NumberFormat('pt-BR', {
        style: 'currency',
        currency: currency?.code || 'BRL',
      }).format(value);

      label = `${label} - Oferta fechada: ${formattedValue}`;
    }

    return {
      label,
      class: 'bg-green-50 text-green-700 dark:bg-green-900 dark:text-green-300',
      icon: 'checkmark-circle',
    };
  }
  if (status === 'lost') {
    return {
      label: 'Perdido',
      class: 'bg-red-50 text-red-700 dark:bg-red-900 dark:text-red-300',
      icon: 'dismiss-circle',
    };
  }
  return null;
};

// Funções para modal de mover funil
const openMoveFunnelModal = async () => {
  try {
    // Buscar todos os funis disponíveis
    const { data } = await FunnelAPI.get();
    availableFunnels.value = data;

    // Pré-selecionar o funil atual
    selectedFunnelId.value = kanbanItemComputed.value?.funnel_id;

    // Encontrar a chave da stage atual baseada no nome armazenado
    const currentFunnel = data.find(
      f => f.id === kanbanItemComputed.value?.funnel_id
    );
    const currentStageName = kanbanItemComputed.value?.funnel_stage;

    if (currentFunnel && currentStageName) {
      // Encontrar a chave da stage baseada no nome
      const stageKey = Object.keys(currentFunnel.stages).find(
        key => currentFunnel.stages[key].name === currentStageName
      );
      selectedStage.value = stageKey || null;
    } else {
      selectedStage.value = null;
    }

    showMoveFunnelModal.value = true;
  } catch (error) {
    console.error('Erro ao carregar funis:', error);
  }
};

const closeMoveFunnelModal = () => {
  showMoveFunnelModal.value = false;
  selectedFunnelId.value = null;
  selectedStage.value = null;
};

const moveItemToFunnel = async () => {
  if (!selectedFunnelId.value || !kanbanItemComputed.value) return;

  try {
    isMovingItem.value = true;

    // Mover o item para o novo funil/etapa
    await KanbanAPI.moveToFunnel(
      kanbanItemComputed.value.id,
      selectedFunnelId.value,
      selectedStage.value
    );

    // Emitir evento para atualizar o kanban
    emitter.emit('kanban.item.updated');

    // Emitir evento para atualizar a conversa se necessário
    if (currentChat.value) {
      emitter.emit('conversation.updated', currentChat.value.id);
    }

    // Fechar modal
    closeMoveFunnelModal();

    emitter.emit('newToastMessage', {
      message: 'Item movido com sucesso',
      type: 'success',
    });
  } catch (error) {
    console.error('Erro ao mover item:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao mover item',
      type: 'error',
    });
  } finally {
    isMovingItem.value = false;
  }
};
</script>

<template>
  <div class="p-4">
    <div v-if="kanbanItemComputed && currentFunnel" class="flex flex-col gap-4">
      <!-- Action Buttons -->
      <div class="grid grid-cols-3 gap-2 w-full">
        <Button
          variant="outline"
          color="slate"
          size="sm"
          class="w-full text-xs"
          @click="openMoveFunnelModal"
        >
          {{ t('KANBAN.CONVERSATION_ACTIONS.MOVE') }}
        </Button>

        <Button
          variant="outline"
          color="slate"
          size="sm"
          class="w-full text-xs"
          @click="openAgentAssignModal"
        >
          {{ t('KANBAN.CONVERSATION_ACTIONS.AGENTS') }}
        </Button>

        <Button
          variant="solid"
          color="blue"
          size="sm"
          class="w-full h-10 text-xs"
          @click="handleShowDetails(kanbanItemComputed)"
        >
          {{ t('KANBAN.CONVERSATION_ACTIONS.DETAILS') }}
        </Button>
      </div>

      <!-- Funnel and Stage Section -->
      <div class="flex items-center justify-between rounded-lg">
        <div class="flex items-center gap-2">
          <span
            class="text-slate-600 dark:text-slate-400 text-xs font-medium"
>{{ t('KANBAN.CONVERSATION_ACTIONS.FUNNEL_LABEL') }}</span>
          <span
            class="text-xs font-medium px-2 py-1 rounded-full"
            :style="funnelStyle"
          >
            {{ currentFunnel.name }}
          </span>
        </div>

        <div class="flex items-center gap-2">
          <span
            class="text-slate-600 dark:text-slate-400 text-xs font-medium"
>{{ t('KANBAN.CONVERSATION_ACTIONS.STAGE_LABEL') }}</span>
          <span
            class="text-xs font-medium px-2 py-1 rounded-full"
            :style="stageStyle"
          >
            {{ kanbanStageLabel }}
          </span>
        </div>
      </div>

      <!-- Time in stage -->
      <div
        v-if="kanbanItemComputed.stage_entered_at"
        class="flex items-center justify-between"
      >
        <span class="text-slate-600 dark:text-slate-400 text-xs font-medium">
          {{ t('KANBAN.CONVERSATION_ACTIONS.TIME_IN_STAGE') }}
        </span>
        <span
          class="text-xs font-medium px-2 py-1 rounded-full flex items-center gap-1"
          :style="funnelStyle"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="12"
            height="12"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="lucide lucide-history-icon lucide-history"
          >
            <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" />
            <path d="M3 3v5h5" />
            <path d="M12 7v5l4 2" />
          </svg>
          {{ formatTimeInStage(kanbanItemComputed.stage_entered_at) }}
        </span>
      </div>

      <!-- Details Section -->
      <div v-if="hasDetailsData" class="flex flex-col gap-3 rounded-lg">
        <div
          v-if="kanbanItemComputed.item_details.value"
          class="flex items-center justify-between"
        >
          <span
            class="text-slate-600 dark:text-slate-400 text-xs font-medium"
>{{ t('KANBAN.CONVERSATION_ACTIONS.VALUE_LABEL') }}</span>
          <span
            class="text-xs font-semibold text-slate-700 dark:text-slate-200"
          >
            {{
              formatCurrency(
                kanbanItemComputed.item_details.value,
                kanbanItemComputed.item_details.currency
              )
            }}
          </span>
        </div>

        <div
          v-if="
            kanbanItemComputed.item_details.priority &&
            kanbanItemComputed.item_details.priority !== 'none'
          "
          class="flex items-center justify-between"
        >
          <span
            class="text-slate-600 dark:text-slate-400 text-xs font-medium"
>{{ t('KANBAN.CONVERSATION_ACTIONS.PRIORITY_LABEL') }}</span>
          <span
            class="text-xs font-medium px-2 py-1 rounded-full"
            :style="priorityStyle"
          >
            {{ priorityLabel }}
          </span>
        </div>

        <div v-if="hasScheduling" class="flex flex-col gap-2">
          <div
            v-if="kanbanItemComputed.item_details.deadline_at"
            class="flex items-center justify-between"
          >
            <span
              class="text-slate-600 dark:text-slate-400 text-xs font-medium flex items-center"
            >
              <i class="icon-calendar-clock text-base align-text-bottom" />
              {{ t('KANBAN.CONVERSATION_ACTIONS.DEADLINE_LABEL') }}
            </span>
            <span class="text-xs text-slate-700 dark:text-slate-200">
              {{ formatDate(kanbanItemComputed.item_details.deadline_at) }}
            </span>
          </div>
          <div
            v-if="kanbanItemComputed.item_details.scheduled_at"
            class="flex items-center justify-between"
          >
            <span
              class="text-slate-600 dark:text-slate-400 text-xs font-medium flex items-center"
            >
              <i class="icon-calendar text-base align-text-bottom" />
              {{ t('KANBAN.CONVERSATION_ACTIONS.SCHEDULED_LABEL') }}
            </span>
            <span class="text-xs text-slate-700 dark:text-slate-200">
              {{ formatDateTime(kanbanItemComputed.item_details.scheduled_at) }}
            </span>
          </div>
        </div>
      </div>

      <!-- Notes Section -->
      <div
        v-if="kanbanItemComputed.item_details.notes?.length"
        class="flex flex-col gap-3"
      >
        <span class="text-slate-600 dark:text-slate-400 text-sm font-medium">{{
          t('KANBAN.CONVERSATION_ACTIONS.NOTES')
        }}</span>
        <div class="flex flex-col gap-2">
          <div
            v-for="note in kanbanItemComputed.item_details.notes"
            :key="note.id"
            class="bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 p-3 rounded-lg shadow-sm"
            style="box-shadow: 0 2px 8px 0 rgba(30, 41, 59, 0.04)"
          >
            <div class="flex items-center justify-between mb-2">
              <div class="flex items-center gap-2">
                <Avatar :name="note.author" :size="20" />
                <span
                  class="text-xs font-medium text-slate-700 dark:text-slate-300"
                >
                  {{ note.author }}
                </span>
              </div>
              <span class="text-[10px] text-slate-500 dark:text-slate-400">
                {{ formatDateTime(note.created_at) }}
              </span>
            </div>
            <div
              class="text-sm text-slate-700 dark:text-slate-200 break-words overflow-hidden prose prose-sm max-w-none dark:prose-invert"
              v-html="renderMarkdown(note.text)"
            />
          </div>
        </div>
      </div>

      <!-- Checklist Section -->
      <div v-if="displayChecklists.length > 0" class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <span
            class="text-slate-600 dark:text-slate-400 text-sm font-medium flex items-center gap-2"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="lucide lucide-list-checks"
            >
              <path d="m3 17 2 2 4-4" />
              <path d="m3 7 2 2 4-4" />
              <path d="M13 6h8" />
              <path d="M13 12h8" />
              <path d="M13 18h8" />
            </svg>
            {{ t('KANBAN.CONVERSATION_ACTIONS.CHECKLIST') }}
          </span>
          <span class="text-xs text-slate-500 dark:text-slate-400">
            {{ checklistStats.completed }}/{{ checklistStats.total }} ({{
              checklistStats.percentage
            }}%)
          </span>
        </div>

        <div class="flex flex-col gap-2">
          <div
            v-for="item in displayChecklists"
            :key="item.id"
            class="bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 p-2 rounded-lg"
          >
            <div class="flex items-start gap-2">
              <div class="flex-shrink-0 mt-0.5">
                <button
                  class="w-4 h-4 rounded flex items-center justify-center cursor-pointer transition-all"
                  :style="{
                    backgroundColor: item.completed ? '#10b981' : 'transparent',
                    borderWidth: '2px',
                    borderStyle: 'solid',
                    borderColor: item.completed ? '#10b981' : '#9ca3af',
                  }"
                  @click.stop="handleToggleChecklistItem(item)"
                >
                  <svg
                    v-if="item.completed"
                    xmlns="http://www.w3.org/2000/svg"
                    width="10"
                    height="10"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="white"
                    stroke-width="3"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                </button>
              </div>
              <div class="flex-1 min-w-0">
                <div
                  class="text-xs text-slate-700 dark:text-slate-200 break-words prose prose-sm max-w-none dark:prose-invert"
                  :class="{ 'line-through opacity-60': item.completed }"
                  v-html="renderMarkdown(item.text)"
                />
                <div v-if="item.due_date" class="flex items-center gap-1 mt-1">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="10"
                    height="10"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    class="text-slate-400"
                  >
                    <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
                    <line x1="16" y1="2" x2="16" y2="6" />
                    <line x1="8" y1="2" x2="8" y2="6" />
                    <line x1="3" y1="10" x2="21" y2="10" />
                  </svg>
                  <span class="text-[10px] text-slate-400">
                    {{ formatDate(item.due_date) }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Empty State -->
    <div
      v-else
      class="flex flex-col items-center justify-center gap-4 text-center p-6 bg-slate-50 dark:bg-slate-800/50 rounded-lg"
    >
      <i class="icon-funnel text-3xl text-slate-400 dark:text-slate-500" />
      <p class="text-sm text-slate-500 dark:text-slate-400">
        {{ t('KANBAN.CONVERSATION_ACTIONS.NO_ITEM_ASSOCIATED') }}
      </p>
      <Button
        variant="solid"
        color="blue"
        size="sm"
        @click="showKanbanForm = true"
      >
        <template #icon>
          <fluent-icon icon="add" size="16" />
        </template>
        {{ t('KANBAN.CONVERSATION_ACTIONS.DEFINE_FUNNEL') }}
      </Button>
    </div>

    <!-- Modal -->
    <Modal
      v-model:show="showKanbanForm"
      size="full-width"
      :on-close="
        () => {
          showKanbanForm = false;
          previewData.value = null;
        }
      "
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4 flex items-center gap-2">
          <i class="icon-funnel text-slate-600 dark:text-slate-400" />
          {{
            kanbanItemComputed
              ? t('KANBAN.CONVERSATION_ACTIONS.EDIT_KANBAN_ITEM')
              : t('KANBAN.CONVERSATION_ACTIONS.CREATE_KANBAN_ITEM')
          }}
        </h3>
        <KanbanItemForm
          v-if="funnels[0]"
          :funnel-id="initialFormData.funnel_id || funnels[0].id"
          :stage="initialFormData.funnel_stage || 'lead'"
          :initial-data="initialFormData"
          :is-editing="!!kanbanItemComputed"
          :current-conversation="currentConversation"
          @saved="handleKanbanFormSave"
          @close="showKanbanForm = false"
          @update:preview="newData => (previewData.value = newData)"
        />
      </div>
    </Modal>

    <!-- Modal de Detalhes -->
    <Modal
      v-model:show="showDetailsModal"
      size="full-width"
      :on-close="
        () => {
          showDetailsModal = false;
          itemToShow.value = null;
          handleDetailsUpdate();
        }
      "
    >
      <div
        class="flex flex-col h-full w-full bg-white dark:bg-slate-900 overflow-hidden"
      >
        <!-- Header igual ao KanbanItemDetailView -->
        <div
          class="border-b border-slate-200 dark:border-slate-700 px-4 py-3 flex items-center justify-between"
        >
          <div class="flex items-center gap-2">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="lucide lucide-chevron-left-icon lucide-chevron-left cursor-pointer text-slate-600 dark:text-slate-400"
              @click="
                () => {
                  showDetailsModal = false;
                  itemToShow.value = null;
                  handleDetailsUpdate();
                }
              "
            >
              <path d="m15 18-6-6 6-6" />
            </svg>
            <div class="flex items-center gap-3">
              <h2 class="text-base font-medium">
                {{ itemToShow?.item_details?.title || 'Detalhes do Item' }}
              </h2>
              <!-- Status do Item -->
              <span
                v-if="itemToShow"
                class="px-2.5 py-1 text-xs font-medium rounded-full"
                :class="getItemStatusClass(itemToShow)"
              >
                {{ getItemStatusLabel(itemToShow) }}
              </span>
              <span
                v-if="itemToShow && getPriorityInfo(itemToShow)"
                class="px-2.5 py-1 text-xs font-medium rounded-full"
                :class="getPriorityInfo(itemToShow).class"
              >
                {{ getPriorityInfo(itemToShow).label }}
              </span>
              <!-- Custom Attributes da Conversa -->
              <div
                v-if="
                  itemToShow &&
                  getConversationCustomAttributes(itemToShow).length > 0
                "
                class="flex items-center gap-2"
              >
                <span
                  v-for="attr in getConversationCustomAttributes(itemToShow)"
                  :key="attr.key"
                  class="px-1.5 py-0.5 text-[10px] font-medium bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300 rounded-full"
                  :title="`${attr.key}: ${attr.value}`"
                >
                  {{ attr.key }}: {{ attr.value }}
                </span>
              </div>
              <!-- Updated At -->
              <div
                v-if="itemToShow && getFormattedUpdatedAt(itemToShow)"
                class="text-[10px] text-slate-500 dark:text-slate-400 ml-2 hidden md:block"
              >
                {{ t('KANBAN.CONVERSATION_ACTIONS.UPDATED_AT') }}
                {{ getFormattedUpdatedAt(itemToShow) }}
              </div>
            </div>
          </div>

          <div v-if="itemToShow" class="flex items-center gap-3 mr-12">
            <!-- Data limite -->
            <div
              v-if="getFormattedDeadlineAt(itemToShow)"
              class="flex items-center gap-1.5 px-3 py-1.5"
              :style="{ backgroundColor: '#fef3c7', borderColor: '#d97706' }"
              style="
                border-width: 1px;
                border-radius: 8px;
                box-shadow: 0 1px 2px 0 rgb(0 0 0 / 0.05);
                transition: all 200ms;
              "
            >
              <fluent-icon
                icon="calendar-clock"
                size="14"
                :style="{ color: '#d97706' }"
                class="drop-shadow-sm"
              />
              <span
                class="text-xs font-medium tracking-wide"
                :style="{ color: '#d97706' }"
              >
                {{ t('KANBAN.CONVERSATION_ACTIONS.DEADLINE_LABEL') }}
                {{ getFormattedDeadlineAt(itemToShow) }}
              </span>
            </div>

            <!-- Botão de mover funil -->
            <button
              class="p-1.5 rounded-md"
              :style="{
                backgroundColor: '#3b82f6',
                color: 'white',
                borderColor: '#2563eb',
              }"
              style="
                border-width: 1px;
                border-radius: 6px;
                box-shadow: 0 1px 2px 0 rgb(0 0 0 / 0.05);
                transition: all 200ms;
              "
              @mouseover="$event.target.style.backgroundColor = '#2563eb'"
              @mouseleave="$event.target.style.backgroundColor = '#3b82f6'"
              @click="openMoveFunnelModal"
            >
              <span class="flex items-center gap-1">
                <fluent-icon icon="arrow-right" size="14" />
                <span class="text-xs">{{
                  t('KANBAN.CONVERSATION_ACTIONS.MOVE_TO_FUNNEL')
                }}</span>
              </span>
            </button>

            <!-- Botão de editar -->
            <button
              class="p-1.5 rounded-md bg-slate-100 dark:bg-slate-800 hover:bg-slate-200 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-300"
              @click="
                () => {
                  showDetailsModal = false;
                  itemToShow.value = null;
                  showKanbanForm = true;
                }
              "
            >
              <span class="flex items-center gap-1">
                <fluent-icon icon="edit" size="14" />
                <span class="text-xs">{{ t('KANBAN.ACTIONS.EDIT') }}</span>
              </span>
            </button>
          </div>
        </div>

        <!-- Status Header -->
        <div
          v-if="getStatusInfo(itemToShow)"
          class="px-4 py-1.5 flex items-center gap-2 text-xs font-medium"
:class="[
          :class="
[getStatusInfo(itemToShow).class]"
        >
          <fluent-icon :icon="getStatusInfo(itemToShow).icon" size="14" />
          <span>{{ getStatusInfo(itemToShow).label }}</span>
          <span
            v-if="itemToShow?.item_details?.reason"
            class="text-[10px] italic"
          >
            - {{ itemToShow.item_details.reason }}
          </span>
        </div>

        <!-- Content -->
        <div class="flex-1 overflow-auto">
          <KanbanItemDetails
            v-if="itemToShow"
            :item-id="itemToShow.id"
            :show-header="false"
            :show-edit-button="false"
            @close="
              () => {
                showDetailsModal = false;
                itemToShow.value = null;
                handleDetailsUpdate();
              }
            "
            @edit="
              () => {
                showDetailsModal = false;
                itemToShow.value = null;
                showKanbanForm = true;
              }
            "
            @item-updated="handleDetailsUpdate"
          />
        </div>
      </div>
    </Modal>

    <!-- Modal de mover funil -->
    <Modal
      v-model:show="showMoveFunnelModal"
      :on-close="closeMoveFunnelModal"
      :show-close-button="true"
      size="medium"
    >
      <div class="p-6">
        <div class="flex items-center gap-3 mb-6">
          <div
            class="flex items-center justify-center w-10 h-10 rounded-lg bg-blue-50 dark:bg-blue-900/20"
          >
            <fluent-icon icon="arrow-right" size="20" class="text-blue-500" />
          </div>
          <h3 class="text-lg font-semibold text-slate-900 dark:text-slate-100">
            {{ t('KANBAN.CONVERSATION_ACTIONS.MOVE_TO_FUNNEL') }}
          </h3>
        </div>

        <div class="space-y-6">
          <!-- Seleção de funil -->
          <div class="space-y-2">
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.CONVERSATION_ACTIONS.FUNNEL_SELECT_LABEL') }}
            </label>
            <select
              v-model="selectedFunnelId"
              class="w-full px-3 py-2.5 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
            >
              <option value="">
                {{ t('KANBAN.CONVERSATION_ACTIONS.SELECT_FUNNEL') }}
              </option>
              <option
                v-for="funnel in availableFunnels"
                :key="funnel.id"
                :value="funnel.id"
              >
                {{ funnel.name }}
              </option>
            </select>
          </div>

          <!-- Seleção de etapa -->
          <div v-if="selectedFunnelForModal" class="space-y-2">
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.CONVERSATION_ACTIONS.STAGE_SELECT_LABEL') }}
            </label>
            <select
              v-model="selectedStage"
              class="w-full px-3 py-2.5 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
            >
              <option value="">
                {{ t('KANBAN.CONVERSATION_ACTIONS.SELECT_STAGE') }}
              </option>
              <option
                v-for="(stage, stageKey) in selectedFunnelForModal.stages"
                :key="stageKey"
                :value="stageKey"
              >
                {{ stage.name }}
              </option>
            </select>
          </div>
        </div>

        <div
          class="flex justify-end gap-3 mt-6 pt-4 border-t border-slate-200 dark:border-slate-700"
        >
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            @click="closeMoveFunnelModal"
          >
            {{ t('KANBAN.CONVERSATION_ACTIONS.CANCEL') }}
          </Button>
          <Button
            variant="solid"
            color="blue"
            size="sm"
            :is-loading="isMovingItem"
            :disabled="!selectedFunnelId || isMovingItem"
            @click="moveItemToFunnel"
          >
            <template v-if="!isMovingItem" #icon>
              <fluent-icon icon="arrow-right" size="16" />
            </template>
            {{
              isMovingItem
                ? t('KANBAN.CONVERSATION_ACTIONS.MOVING')
                : t('KANBAN.CONVERSATION_ACTIONS.MOVE_BUTTON')
            }}
          </Button>
        </div>
      </div>
    </Modal>

    <!-- Modal de atribuição rápida de agente -->
    <Modal
      v-model:show="showAgentAssignModal"
      :on-close="() => (showAgentAssignModal = false)"
      :show-close-button="true"
      size="medium"
    >
      <div
        class="p-4 bg-white dark:bg-slate-900 rounded-md border border-slate-100 dark:border-slate-800 shadow-lg"
      >
        <h3 class="text-lg font-medium mb-4">
          {{ t('KANBAN.CONVERSATION_ACTIONS.MANAGE_ASSIGNED_AGENTS') }}
        </h3>

        <!-- Seção de agentes já atribuídos -->
        <div v-if="agentInfo.length > 0" class="mb-4">
          <h4
            class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-2"
          >
            {{ t('KANBAN.CONVERSATION_ACTIONS.ASSIGNED_AGENTS') }} ({{
              agentInfo.length
            }})
            {{
              console.log(
                '[KanbanActions] Rendering assigned agents section:',
                agentInfo
              ) || ''
            }}
          </h4>
          <div class="space-y-2">
            <div
              v-for="agent in agentInfo"
              :key="agent.id"
              class="flex items-center justify-between p-2 bg-slate-50 dark:bg-slate-800 rounded-md"
            >
              <div class="flex items-center gap-2">
                <Avatar
                  :name="agent.name"
                  :src="agent.avatar_url || ''"
                  :size="24"
                />
                <div>
                  <div
                    class="text-sm font-medium text-slate-900 dark:text-slate-100"
                  >
                    {{ agent.name }}
                  </div>
                  <div class="text-xs text-slate-500 dark:text-slate-400">
                    {{ t('KANBAN.CONVERSATION_ACTIONS.ASSIGNED_ON') }}
                    {{
                      new Date(agent.assigned_at).toLocaleDateString('pt-BR')
                    }}
                  </div>
                </div>
              </div>
              <button
                class="p-1 text-slate-400 hover:text-red-500 transition-colors"
                @click="removeAgent(agent.id)"
              >
                <fluent-icon icon="delete" size="16" />
              </button>
            </div>
          </div>
        </div>

        <!-- Seção para adicionar novos agentes -->
        <div class="border-t border-slate-200 dark:border-slate-700 pt-4">
          <h4
            class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-2"
          >
            {{ t('KANBAN.CONVERSATION_ACTIONS.ADD_NEW_AGENT') }}
          </h4>
          <input
            v-model="agentSearch"
            type="text"
            class="w-full mb-3 px-3 py-2 border border-slate-100 dark:border-slate-800 rounded-md text-xs bg-white dark:bg-slate-800 focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
            :placeholder="t('KANBAN.CONVERSATION_ACTIONS.SEARCH_AGENTS')"
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
                agentInfo.some(a => a.id === agent.id)
                  ? 'opacity-50 cursor-not-allowed'
                  : '',
              ]"
              :disabled="agentInfo.some(a => a.id === agent.id)"
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
                v-if="agentInfo.some(a => a.id === agent.id)"
                class="ml-auto text-slate-400 text-xs"
                >{{ t('KANBAN.CONVERSATION_ACTIONS.ALREADY_ASSIGNED') }}</span>
              <span
                v-else-if="selectedAgentId === agent.id"
                class="ml-auto text-woot-500 text-xs font-semibold"
                >{{ t('KANBAN.CONVERSATION_ACTIONS.SELECTED') }}</span>
            </button>
            <div
              v-if="filteredAgentList.length === 0"
              class="px-3 py-2 text-slate-400 text-xs"
            >
              {{ t('KANBAN.CONVERSATION_ACTIONS.NO_AGENT_FOUND') }}
            </div>
          </div>
        </div>

        <div class="flex justify-end gap-2 mt-4">
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            @click="showAgentAssignModal = false"
          >
            {{ t('KANBAN.CONVERSATION_ACTIONS.CLOSE') }}
          </Button>
          <Button
            variant="solid"
            color="blue"
            size="sm"
            :is-loading="agentAssignLoading"
            :disabled="
              !selectedAgentId ||
              agentAssignLoading ||
              agentInfo.some(a => a.id === selectedAgentId)
            "
            @click="assignAgent"
          >
            {{ t('KANBAN.CONVERSATION_ACTIONS.ADD_AGENT') }}
          </Button>
        </div>
      </div>
    </Modal>
  </div>
</template>

<style scoped>
/* Estilos específicos para o conteúdo markdown das notas */
.note-content :deep(ul),
.note-content :deep(ol) {
  margin: 0.5rem 0;
  padding-left: 1.5rem;
}

.note-content :deep(li) {
  margin: 0.25rem 0;
  padding-left: 0.25rem;
}

.note-content :deep(ul ul),
.note-content :deep(ol ol),
.note-content :deep(ul ol),
.note-content :deep(ol ul) {
  margin: 0.25rem 0;
  padding-left: 1rem;
}

/* Garante que as bolinhas das listas não vazem */
.note-content :deep(.note-text) {
  contain: layout style paint;
}

/* Estilos para markdown renderizado */
.prose {
  font-size: 14px !important;
  @apply leading-relaxed;

  :deep(p) {
    @apply mb-2 last:mb-0;
    font-size: 14px !important;
  }

  :deep(ul) {
    @apply list-disc list-inside mb-2 space-y-1;
  }

  :deep(ol) {
    @apply list-decimal list-inside mb-2 space-y-1;
  }

  :deep(li) {
    @apply leading-relaxed;
    font-size: 14px !important;
  }

  :deep(strong) {
    @apply font-semibold;
    font-size: 14px !important;
  }

  :deep(em) {
    @apply italic;
    font-size: 14px !important;
  }

  :deep(code) {
    @apply bg-slate-100 dark:bg-slate-800 px-1 py-0.5 rounded font-mono;
    font-size: 13px !important;
  }

  :deep(pre) {
    @apply bg-slate-100 dark:bg-slate-800 p-2 rounded font-mono overflow-x-auto mb-2;
    font-size: 13px !important;
  }

  :deep(a) {
    @apply text-woot-500 hover:text-woot-600 underline;
    font-size: 14px !important;
  }
}
</style>
