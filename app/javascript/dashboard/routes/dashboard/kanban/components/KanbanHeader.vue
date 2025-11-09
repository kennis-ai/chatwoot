<script setup>
import { ref, computed, nextTick, watch, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useConfig } from 'dashboard/composables/useConfig';
import { emitter } from 'shared/helpers/mitt';
import Modal from '../../../../components/Modal.vue';
import KanbanItemForm from './KanbanItemForm.vue';
import FunnelSelector from './FunnelSelector.vue';
import KanbanSettings from './KanbanSettings.vue';
import BulkDeleteModal from './BulkDeleteModal.vue';
import BulkMoveModal from './BulkMoveModal.vue';
import BulkAddModal from './BulkAddModal.vue';
import KanbanAPI from '../../../../api/kanban';
import KanbanFilter from './KanbanFilter.vue';
import KanbanAI from './KanbanAI.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import FunnelAPI from '../../../../api/funnel';
import FunnelForm from './FunnelForm.vue';
import BulkSendMessageModal from './BulkSendMessageModal.vue';
import Dragbar from './Dragbar.vue';
import AgentTooltip from './AgentTooltip.vue';
import agents from '../../../../api/agents';
import inboxes from '../../../../api/inboxes';

const props = defineProps({
  currentStage: {
    type: String,
    default: '',
  },
  searchResults: {
    type: Object,
    default: () => ({ total: 0, stages: {} }),
  },
  columns: {
    type: Array,
    default: () => [],
  },
  activeFilters: {
    type: Object,
    default: null,
  },
  currentView: {
    type: String,
    default: 'kanban',
  },
  kanbanItems: {
    type: Array,
    required: true,
  },
  isDraggingActive: {
    type: Boolean,
    default: false,
  },
  draggedItem: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits([
  'openFilterModal',
  'itemCreated',
  'search',
  'itemsUpdated',
  'switchView',
  'newToastMessage',
  'globalStatusFilterChange',
  'filterApplied',
  'globalFilterChange',
  'searchResults',
]);

// Função utilitária de debounce
const debounce = (fn, delay) => {
  let timeoutId;
  return (...args) => {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => fn(...args), delay);
  };
};

const { t } = useI18n();
const store = useStore();
const { isStacklab } = useConfig();

// Adicionar um watcher para monitorar mudanças
watch(
  () => isStacklab,
  newValue => {
    // Watcher vazio mantido para possível uso futuro
  }
);

const showAddModal = ref(false);
const selectedFunnel = computed(
  () => store.getters['funnel/getSelectedFunnel']
);

const showSettingsModal = ref(false);
const showFilterModal = ref(false);

const showSearchInput = ref(false);
const searchQuery = ref('');
const isSearching = ref(false);
const searchResults = ref(null);

const showBulkActions = ref(false);

const showHiddenStages = ref(false);

const globalStatusFilters = ref({ won: false, lost: false });

// +++ Filter state +++
const selectedAgentFilter = ref('');
const selectedChannelFilter = ref('');

// +++ Custom dropdown states +++
const showAgentDropdown = ref(false);
const showChannelDropdown = ref(false);

// +++ Reactive variable for Quick Message toggle +++
const isQuickMessageActive = computed(
  () => store.getters['kanban/getQuickMessageEnabled']
);

const toggleGlobalStatusFilter = statusType => {
  if (statusType === 'won') {
    globalStatusFilters.value.won = !globalStatusFilters.value.won;
  } else if (statusType === 'lost') {
    globalStatusFilters.value.lost = !globalStatusFilters.value.lost;
  }
  emit('globalStatusFilterChange', { ...globalStatusFilters.value });
};

const handleQuickMessageClick = async () => {
  try {
    // +++ Toggle the state and update store +++
    const newState = !isQuickMessageActive.value;
    await store.dispatch('kanban/updateQuickMessageConfig', newState);
  } catch (error) {
    console.error('Erro ao atualizar configuração de mensagem rápida:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao atualizar configuração de mensagem rápida',
      action: { type: 'error' },
    });
  }
};

const bulkActions = [
  {
    id: 'add',
    label: t('KANBAN.BULK_ACTIONS.ADD.TITLE'),
    icon: 'add',
  },
  {
    id: 'move',
    label: t('KANBAN.BULK_ACTIONS.MOVE.TITLE'),
    icon: 'arrow-right',
  },
  {
    id: 'delete',
    label: t('KANBAN.BULK_ACTIONS.DELETE.TITLE'),
    icon: 'delete',
  },
  {
    id: 'show_hidden',
    label: t('KANBAN.BULK_ACTIONS.SHOW_HIDDEN'),
    icon: 'eye-show',
  },
  {
    id: 'send_message',
    label: t('KANBAN.BULK_ACTIONS.SEND_MESSAGE.TITLE'),
    icon: 'chat',
  },
];

const filteredBulkActions = computed(() => {
  return bulkActions.filter(
    action => action.id !== 'send_message' || isStacklab === true
  );
});

const showBulkDeleteModal = ref(false);
const showBulkMoveModal = ref(false);
const showBulkAddModal = ref(false);

const showSettingsDropdown = ref(false);
const showAddDropdown = ref(false);

const userIsAdmin = computed(() => {
  const currentUser = store.getters.getCurrentUser;
  return currentUser?.role === 'administrator';
});

const settingsOptions = computed(() => {
  const options = [
    {
      id: 'kanban_settings',
      label: t('KANBAN.MORE_OPTIONS.KANBAN_SETTINGS'),
      icon: 'settings',
    },
  ];

  if (isStacklab === true) {
    options.unshift({
      id: 'offers',
      label: 'Ofertas',
      icon: 'package-search',
      customSvg: true,
    });

    options.push({
      id: 'message_templates',
      label: t('KANBAN.MORE_OPTIONS.MESSAGE_TEMPLATES'),
      icon: 'document',
    });
  }

  if (userIsAdmin.value) {
    options.unshift({
      id: 'manage_funnels',
      label: t('KANBAN.MORE_OPTIONS.MANAGE_FUNNELS'),
      icon: 'task',
    });
  }

  return options;
});

const handleSettingsOption = option => {
  if (option.id === 'kanban_settings') {
    showSettingsModal.value = true;
  } else if (option.id === 'manage_funnels') {
    emit('switchView', 'funnels');
  } else if (option.id === 'offers') {
    emit('switchView', 'offers');
  } else if (option.id === 'message_templates') {
    handleMessageTemplates();
  }
  showSettingsDropdown.value = false;
};

const handleSettingsClick = () => {
  showSettingsDropdown.value = !showSettingsDropdown.value;
};

const handleBulkActions = () => {
  showBulkActions.value = !showBulkActions.value;
};

const selectBulkAction = action => {
  if (action.id === 'show_hidden') {
    showHiddenStages.value = !showHiddenStages.value;

    // Verifica se existem colunas ocultas antes de alterar
    const hasHiddenColumns = props.columns.some(column => {
      const settings = JSON.parse(
        localStorage.getItem(`kanban_column_${column.id}_settings`) || '{}'
      );
      return settings.hideColumn === true;
    });

    // Só altera se existirem colunas ocultas ou se estiver desativando
    if (hasHiddenColumns || !showHiddenStages.value) {
      props.columns.forEach(column => {
        const settings = JSON.parse(
          localStorage.getItem(`kanban_column_${column.id}_settings`) || '{}'
        );

        // Só altera se a coluna estiver oculta
        if (settings.hideColumn === true) {
          settings.hideColumn = !showHiddenStages.value;
          localStorage.setItem(
            `kanban_column_${column.id}_settings`,
            JSON.stringify(settings)
          );
        }
      });

      emit('itemsUpdated');
    }
  } else if (action.id === 'delete') {
    showBulkDeleteModal.value = true;
  } else if (action.id === 'move') {
    showBulkMoveModal.value = true;
  } else if (action.id === 'add') {
    showBulkAddModal.value = true;
  } else if (action.id === 'send_message') {
    showSendMessageModal.value = true;
  }
  showBulkActions.value = false;
};

const handleFilter = () => {
  showFilterModal.value = true;
};

const handleFilterApply = filters => {
  console.log('[KanbanHeader] handleFilterApply - Filtros recebidos:', filters);

  // Mapear filtros do KanbanFilter para o formato esperado pelo sistema
  const mappedFilters = {
    priority: filters.priorities || [],
    value: {
      min: filters.valueMin || null,
      max: filters.valueMax || null,
    },
    agent: filters.agent || '',
    agent_id: filters.agent || '',
    channel: '',
    date: {
      start: filters.dateStart || '',
      end: filters.dateEnd || '',
    },
    scheduledDate: {
      start: filters.scheduledDateStart || '',
      end: filters.scheduledDateEnd || '',
    },
  };

  console.log(
    '[KanbanHeader] handleFilterApply - Filtros mapeados:',
    mappedFilters
  );
  emit('filterApplied', mappedFilters);
  console.log(
    '[KanbanHeader] handleFilterApply - Emit filterApplied realizado'
  );
  showFilterModal.value = false;
};

const handleFilterResults = results => {
  console.log(
    '[KanbanHeader] handleFilterResults - Resultados recebidos:',
    results
  );

  // Emitir resultados para o componente pai (similar ao searchResults)
  emit('searchResults', results);
  console.log(
    '[KanbanHeader] handleFilterResults - Emit searchResults realizado'
  );
};

const handleSettings = () => {
  showSettingsModal.value = true;
};

const handleCloseSettings = () => {
  showSettingsModal.value = false;
};

const handleAdd = () => {
  showAddDropdown.value = !showAddDropdown.value;
};

const handleNewItem = () => {
  if (!selectedFunnel.value?.id) {
    emit('newToastMessage', {
      message: t('KANBAN.ERRORS.NO_FUNNEL_SELECTED'),
      action: { type: 'error' },
    });
    return;
  }
  showAddModal.value = true;
  showAddDropdown.value = false;
};

const handleItemCreated = async item => {
  emit('itemCreated', item);
  showAddModal.value = false;
};

const handleSearch = () => {
  showSearchInput.value = !showSearchInput.value;
  if (showSearchInput.value) {
    nextTick(() => {
      document.getElementById('kanban-search').focus();
    });
  } else {
    // Limpa a busca ao fechar
    searchQuery.value = '';
    searchResults.value = null;
    emit('search', '');
    emit('searchResults', null);
  }
};

// Função para executar busca via API
const performSearch = async query => {
  if (!query || query.trim().length < 2) {
    searchResults.value = null;
    emit('searchResults', null);
    return;
  }

  try {
    isSearching.value = true;
    const response = await KanbanAPI.searchItems(query.trim());
    searchResults.value = response.data;
    emit('searchResults', response.data);
  } catch (error) {
    console.error('Erro ao buscar itens:', error);
    searchResults.value = null;
    emit('searchResults', null);
    emitter.emit('newToastMessage', {
      message: 'Erro ao buscar itens',
      action: { type: 'error' },
    });
  } finally {
    isSearching.value = false;
  }
};

// Watch para manter o input visível enquanto houver busca e executar busca
watch(searchQuery, (newValue, oldValue) => {
  if (newValue) {
    showSearchInput.value = true;
  }
  // Emitir busca local para compatibilidade
  emit('search', newValue || '');

  // Executar busca via API com debounce
  debounce(performSearch, 300)(newValue);
});

const handleBulkDelete = async selectedIds => {
  try {
    // Processar cada item individualmente para emitir eventos corretos
    const deletePromises = selectedIds.map(async itemId => {
      // Executar exclusão via API
      await KanbanAPI.deleteItem(itemId);

      // Emitir evento para atualizar colunas em tempo real
      emitter.emit('kanbanItemDeleted', { itemId: parseInt(itemId, 10) });

      return itemId;
    });

    await Promise.all(deletePromises);

    showBulkDeleteModal.value = false;
    emit('itemsUpdated');
  } catch (error) {
    console.error('Erro ao excluir itens:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao excluir itens em massa',
      type: 'error',
    });
  }
};

const handleBulkMove = async ({ itemIds, stageId }) => {
  try {
    // Processar cada item individualmente para emitir eventos corretos
    const movePromises = itemIds.map(async itemId => {
      // Obter dados do item antes do movimento
      const { data: currentItem } = await KanbanAPI.getItem(itemId);
      const fromStage = currentItem.funnel_stage;

      // Executar movimento
      await KanbanAPI.moveToStage(itemId, stageId);

      // Obter dados do item atualizado
      const { data: updatedItem } = await KanbanAPI.getItem(itemId);

      // Emitir eventos para atualizar colunas em tempo real
      emitter.emit('kanbanItemMoved', {
        itemId: parseInt(itemId, 10),
        fromStage: fromStage,
        toStage: stageId,
        itemData: updatedItem,
      });

      // Emitir evento para atualizar stats das colunas
      emitter.emit('kanbanItemMovedBetweenStages', {
        itemId: parseInt(itemId, 10),
        fromStage: fromStage,
        toStage: stageId,
        funnelId: selectedFunnel.value?.id,
      });

      return updatedItem;
    });

    await Promise.all(movePromises);

    showBulkMoveModal.value = false;
    emit('itemsUpdated');
  } catch (error) {
    console.error('Erro ao mover itens:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao mover itens em massa',
      type: 'error',
    });
  }
};

const handleBulkItemsCreated = async createdItems => {
  try {
    // Processar cada item criado para emitir eventos corretos
    if (createdItems && Array.isArray(createdItems)) {
      createdItems.forEach(item => {
        // Emitir evento para atualizar colunas em tempo real
        emitter.emit('kanbanItemCreated', item);
      });
    }

    showBulkAddModal.value = false;
    emit('itemsUpdated');
  } catch (error) {
    console.error('Erro ao processar itens criados:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao processar itens criados em massa',
      type: 'error',
    });
  }
};

// Função para obter a cor da etapa
const getStageColor = stageName => {
  const column = props.columns.find(col => col.title === stageName);
  return column?.color ? `${column.color}` : '#64748B';
};

const handleMessageTemplates = () => {
  emit('switchView', 'templates');
};

// +++ Filter handlers (legacy - kept for compatibility) +++

const emitFilters = () => {
  const filters = {
    agent_id: selectedAgentFilter.value || undefined,
    channel: selectedChannelFilter.value || undefined,
  };

  // Remove undefined values
  Object.keys(filters).forEach(key => {
    if (filters[key] === undefined) {
      delete filters[key];
    }
  });

  emit('globalFilterChange', filters);
};

// +++ Custom dropdown selection functions +++
const selectAgent = agentId => {
  selectedAgentFilter.value = agentId;
  showAgentDropdown.value = false;
  emitFilters();
};

const selectChannel = channelValue => {
  selectedChannelFilter.value = channelValue;
  showChannelDropdown.value = false;
  emitFilters();
};

// Computed para contar filtros ativos
const activeFiltersCount = computed(() => {
  if (!props.activeFilters) return 0;

  let count = 0;
  if (props.activeFilters.priority?.length) count++;
  if (props.activeFilters.value?.min || props.activeFilters.value?.max) count++;
  if (props.activeFilters.agent_id || props.activeFilters.agent) count++;
  if (props.activeFilters.channel) count++;
  if (props.activeFilters.date?.start || props.activeFilters.date?.end) count++;
  if (
    props.activeFilters.scheduledDate?.start ||
    props.activeFilters.scheduledDate?.end
  )
    count++;

  return count;
});

// Computed para converter filtros mapeados para formato esperado pelo KanbanFilter
const kanbanFilterInitialFilters = computed(() => {
  if (!props.activeFilters) return {};

  return {
    priorities: props.activeFilters.priority || [],
    valueMin: props.activeFilters.value?.min || null,
    valueMax: props.activeFilters.value?.max || null,
    agent: props.activeFilters.agent || '',
    dateStart: props.activeFilters.date?.start || '',
    dateEnd: props.activeFilters.date?.end || '',
    scheduledDateStart: props.activeFilters.scheduledDate?.start || '',
    scheduledDateEnd: props.activeFilters.scheduledDate?.end || '',
  };
});

const handleViewChange = view => {
  emit('switchView', view);
};

const showAIModal = ref(false);

// Usar getter do store para obter agentes
const filteredAgents = computed(() => {
  // Usar os agentes do funil atual
  const agentsFromFunnel = selectedFunnel.value?.settings?.agents || [];

  if (!searchQuery.value) return agentsFromFunnel;

  const query = searchQuery.value.toLowerCase();
  return agentsFromFunnel.filter(
    agent =>
      agent &&
      agent.name &&
      agent.email &&
      (agent.name.toLowerCase().includes(query) ||
        agent.email.toLowerCase().includes(query))
  );
});

// +++ Reactive state for agents +++
const availableAgents = ref([]);
const loadingAgents = ref(false);

// +++ Reactive state for inboxes +++
const availableInboxes = ref([]);
const loadingInboxes = ref(false);

// +++ Computed properties for filters +++
const filterAgents = computed(() => {
  return availableAgents.value;
});

const filterChannels = computed(() => {
  return availableInboxes.value
    .map(inbox => ({
      value: inbox.channel_type?.replace('Channel::', '') || '',
      label: inbox.name || inbox.channel_type?.replace('Channel::', '') || '',
    }))
    .filter(channel => channel.value); // Remove entries with empty values
});

const handleAIClick = () => {
  showAIModal.value = true;
};

const toggleAgent = async agent => {
  try {
    const currentAgents = selectedFunnel.value.settings?.agents || [];
    const index = currentAgents.findIndex(a => a.id === agent.id);

    let updatedAgents;
    if (index === -1) {
      updatedAgents = [...currentAgents, agent];
    } else {
      updatedAgents = currentAgents.filter(a => a.id !== agent.id);
    }

    // Prepara o payload mantendo todos os dados existentes
    const payload = {
      ...selectedFunnel.value,
      settings: {
        ...selectedFunnel.value.settings,
        agents: updatedAgents,
        optimization_history:
          selectedFunnel.value.settings?.optimization_history || [],
      },
      stages: Object.entries(selectedFunnel.value.stages || {}).reduce(
        (acc, [id, stage]) => ({
          ...acc,
          [id]: {
            ...stage,
            message_templates: stage.message_templates || [], // Mantém os templates
          },
        }),
        {}
      ),
    };

    // Atualiza o funil
    await FunnelAPI.update(selectedFunnel.value.id, payload);
    await store.dispatch('funnel/fetch');
  } catch (error) {
    console.error('Erro ao atualizar agentes:', error);
  }
};

// +++ Function to fetch agents from API +++
const fetchAgents = async () => {
  try {
    loadingAgents.value = true;
    const { data } = await agents.get();
    availableAgents.value = data;
  } catch (error) {
    console.error('Erro ao carregar agentes:', error);
    availableAgents.value = [];
  } finally {
    loadingAgents.value = false;
  }
};

// +++ Function to fetch inboxes from API +++
const fetchInboxes = async () => {
  try {
    loadingInboxes.value = true;
    const { data } = await inboxes.get();
    // Handle API response structure - data might be wrapped in payload
    availableInboxes.value = data.payload || data || [];
  } catch (error) {
    console.error('Erro ao carregar inboxes:', error);
    availableInboxes.value = [];
  } finally {
    loadingInboxes.value = false;
  }
};

onMounted(async () => {
  // Fetch agents and inboxes on component mount
  await Promise.all([fetchAgents(), fetchInboxes()]);

  // Emit initial global status filters to ensure filtering works from the start
  emit('globalStatusFilterChange', { ...globalStatusFilters.value });

  document.addEventListener('click', event => {
    const target = event.target;
    const isDropdownClick = target.closest(
      '.settings-selector, .bulk-actions-selector, .kanban-add-item-trigger, .agent-filter-dropdown, .channel-filter-dropdown'
    );

    if (!isDropdownClick) {
      closeDropdowns();
    }
  });
});

onUnmounted(() => {
  document.removeEventListener('click', closeDropdowns);
});

// Adicionar ref para controlar modal
const showSendMessageModal = ref(false);
// Adicionar ref para controlar modal de compartilhamento
const showShareModal = ref(false);

// Função para filtrar itens com conversa
const itemsWithConversation = computed(() => {
  return props.kanbanItems.filter(item => item.item_details?.conversation_id);
});

// Função para enviar mensagem em massa
const handleMessageSent = async () => {
  showSendMessageModal.value = false;
  emit('newToastMessage', {
    message: 'Mensagens enviadas com sucesso',
    action: { type: 'success' },
  });
};

// Adicionar ref para controlar modal de visualização
const showViewModal = ref(false);

const closeDropdowns = () => {
  showSettingsDropdown.value = false;
  showAddDropdown.value = false;
  showBulkActions.value = false;
  showAgentDropdown.value = false;
  showChannelDropdown.value = false;
};

// +++ Controle de visibilidade da DragBar
const dragbarEnabled = ref(
  localStorage.getItem('kanban_dragbar_enabled') !== 'false'
);

const handleDragbarVisibilityChanged = value => {
  dragbarEnabled.value = value;
};

const viewOptions = [
  { id: 'kanban', label: 'Kanban', icon: 'task' },
  { id: 'list', label: 'Lista', icon: 'list' },
  { id: 'agenda', label: 'Agenda', icon: 'calendar' },
];

// --- AGENTES PARA MODAL DE COMPARTILHAMENTO ---
const shareAgentsList = ref([]);
const shareAgentSearch = ref('');
const loadingShareAgents = ref(false);

const fetchShareAgents = async () => {
  try {
    loadingShareAgents.value = true;
    const { data } = await agents.get();
    shareAgentsList.value = data;
  } catch (error) {
    console.error('Erro ao carregar agentes:', error);
  } finally {
    loadingShareAgents.value = false;
  }
};

watch(showShareModal, val => {
  if (val) fetchShareAgents();
});

const filteredShareAgents = computed(() => {
  if (!shareAgentSearch.value) return shareAgentsList.value;
  return shareAgentsList.value.filter(
    a =>
      a.name.toLowerCase().includes(shareAgentSearch.value.toLowerCase()) ||
      a.email.toLowerCase().includes(shareAgentSearch.value.toLowerCase())
  );
});

const isAgentSelected = agent => {
  return selectedFunnel.value?.settings?.agents?.some(a => a.id === agent.id);
};

const toggleShareAgent = async agent => {
  try {
    const currentAgents = selectedFunnel.value.settings?.agents || [];
    const index = currentAgents.findIndex(a => a.id === agent.id);
    let updatedAgents;
    if (index === -1) {
      updatedAgents = [...currentAgents, agent];
    } else {
      updatedAgents = currentAgents.filter(a => a.id !== agent.id);
    }
    const payload = {
      ...selectedFunnel.value,
      settings: {
        ...selectedFunnel.value.settings,
        agents: updatedAgents,
        optimization_history:
          selectedFunnel.value.settings?.optimization_history || [],
      },
      stages: Object.entries(selectedFunnel.value.stages || {}).reduce(
        (acc, [id, stage]) => ({
          ...acc,
          [id]: {
            ...stage,
            message_templates: stage.message_templates || [],
          },
        }),
        {}
      ),
    };
    await FunnelAPI.update(selectedFunnel.value.id, payload);
    await store.dispatch('funnel/fetch');
  } catch (error) {
    console.error('Erro ao atualizar agentes:', error);
  }
};
// --- MODAL DE COMPARTILHAMENTO ---
</script>

<template>
  <header
    class="kanban-header-custom relative z-10 flex justify-between items-center pt-2 px-4 dark:border-slate-800 flex-wrap md:pt-3 md:px-6 md:gap-4"
  >
    <div class="flex items-center gap-1 min-w-0 md:gap-2">
      <button
        v-if="isStacklab === true"
        class="kanban-ai-button md:flex hidden mr-1"
        @click="handleAIClick"
      >
        <svg
          class="lightning-icon"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path d="M13 3L4 14H12L11 21L20 10H12L13 3Z" fill="currentColor" />
        </svg>
        <span class="ai-button-text">Kanban AI</span>
      </button>

      <!-- Botão para selecionar visualização no mobile -->
      <button
        class="view-select-btn md:hidden flex items-center gap-1 px-2 py-1.5 rounded-lg bg-slate-100 dark:bg-slate-700"
        @click="showViewModal = true"
      >
        <fluent-icon
          :icon="
            currentView === 'kanban'
              ? 'task'
              : currentView === 'list'
                ? 'list'
                : 'calendar'
          "
          size="16"
        />
        <fluent-icon icon="chevron-down" size="12" />
      </button>

      <!-- Seletor de views expandível no hover -->
      <div class="view-selector hidden md:flex">
        <div class="view-buttons-container">
          <Button
            v-for="option in viewOptions"
            :key="option.id"
            type="button"
            variant="outline"
            color="slate"
            size="sm"
            class="view-button"
            :class="{
              active: currentView === option.id,
              inactive: currentView !== option.id,
            }"
            @click="emit('switchView', option.id)"
          >
            <template #icon>
              <fluent-icon
                v-if="
                  typeof option.icon === 'string' && option.icon.trim() !== ''
                "
                :icon="option.icon"
                size="16"
              />
            </template>
            <span class="view-text">{{ option.label }}</span>
          </Button>
        </div>
      </div>
      <!-- Fim do seletor customizado -->
      <FunnelSelector class="md:block hidden ml-1" />

      <!-- Filtros globais (Ganhos e Perdidos) -->
      <div class="flex items-center gap-1">
        <Button
          type="button"
          variant="outline"
          color="slate"
          size="sm"
          class="group"
          :class="
            globalStatusFilters.won
              ? 'bg-green-50 border-green-200 text-green-700'
              : ''
          "
          @click="toggleGlobalStatusFilter('won')"
        >
          <template #icon>
            <fluent-icon icon="checkmark-circle" size="16" />
          </template>
          <span class="hidden group-hover:inline text-[12px]">{{
            $t('KANBAN.FILTERS.WON')
          }}</span>
        </Button>
        <Button
          type="button"
          variant="outline"
          color="slate"
          size="sm"
          class="group"
          :class="
            globalStatusFilters.lost
              ? 'bg-red-50 border-red-200 text-red-700'
              : ''
          "
          @click="toggleGlobalStatusFilter('lost')"
        >
          <template #icon>
            <fluent-icon icon="dismiss-circle" size="16" />
          </template>
          <span class="hidden group-hover:inline text-[12px]">{{
            $t('KANBAN.FILTERS.LOST')
          }}</span>
        </Button>
      </div>
      <div
        class="md:flex hidden items-center relative gap-1"
        :class="{ 'is-active': showSearchInput }"
      >
        <Button variant="ghost" color="slate" size="sm" @click="handleSearch">
          <template #icon>
            <fluent-icon icon="search" size="16" />
          </template>
        </Button>
        <div
          v-show="showSearchInput || searchQuery"
          class="search-input-wrapper"
        >
          <input
            id="kanban-search"
            v-model="searchQuery"
            type="search"
            class="search-input"
            :placeholder="t('KANBAN.SEARCH.INPUT_PLACEHOLDER')"
            @blur="!searchQuery && (showSearchInput = false)"
          />
        </div>
        <!-- Badge de resultados ocultado conforme solicitado -->
        <!--
        <div
          v-show="showSearchInput && searchQuery"
          class="search-results-tags"
        >
          <div class="search-results-tag">
            {{ searchResults.total || 0 }} resultado{{ (searchResults.total || 0) !== 1 ? 's' : '' }}
          </div>
          <div
            v-for="(count, stageName) in searchResults.stages"
            :key="stageName"
            class="search-results-tag"
            :style="{ backgroundColor: getStageColor(stageName) }"
          >
            <span class="stage-name">{{ stageName }}</span>
            <span class="count-badge">{{ count }}</span>
          </div>
        </div>
        -->
      </div>
    </div>
    <div class="flex items-center gap-1 md:gap-2">
      <!-- +++ Agent and Channel Filters +++ -->
      <div class="flex items-center gap-2 md:flex hidden">
        <!-- Custom Agent Filter -->
        <div class="relative agent-filter-dropdown">
          <div
            class="px-3 py-1.5 text-[12px] border border-slate-300 dark:border-slate-600 rounded-lg bg-slate-50 dark:bg-slate-800 text-slate-700 dark:text-slate-200 cursor-pointer opacity-50 hover:opacity-100 hover:border-slate-400 dark:hover:border-slate-500 transition-all duration-200 flex items-center justify-between"
            :class="[
              { 'ring-2 ring-blue-500 border-transparent': showAgentDropdown },
              selectedAgentFilter ? 'min-w-[140px]' : 'w-auto',
            ]"
            @click="showAgentDropdown = !showAgentDropdown"
          >
            <div class="flex items-center gap-2 min-w-0 flex-1">
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
                class="lucide lucide-user-icon lucide-user flex-shrink-0"
              >
                <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2" />
                <circle cx="12" cy="7" r="4" />
              </svg>
              <span v-if="selectedAgentFilter" class="truncate">
                {{
                  filterAgents.find(a => a.id === selectedAgentFilter)?.name ||
                  'Agente não encontrado'
                }}
              </span>
            </div>
            <svg
              v-if="selectedAgentFilter"
              xmlns="http://www.w3.org/2000/svg"
              width="14"
              height="14"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="lucide lucide-chevron-down-icon lucide-chevron-down ml-2 text-black/70 dark:text-slate-400 flex-shrink-0"
            >
              <path d="m6 9 6 6 6-6" />
            </svg>
          </div>
          <div
            v-if="showAgentDropdown"
            class="absolute top-full left-0 mt-1 bg-white dark:bg-slate-700 border border-slate-300 dark:border-slate-600 rounded-lg shadow-lg z-50 min-w-[140px] max-h-48 overflow-y-auto"
          >
            <div
              class="px-3 py-2 text-[12px] text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-600 cursor-pointer first:rounded-t-lg flex items-center gap-2"
              @click="selectAgent('')"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="lucide lucide-user-icon lucide-user flex-shrink-0"
              >
                <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2" />
                <circle cx="12" cy="7" r="4" />
              </svg>
              {{ $t('KANBAN.FILTER.ALL_AGENTS') }}
            </div>
            <div
              v-for="agent in filterAgents"
              :key="agent.id"
              class="px-3 py-2 text-[12px] text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-600 cursor-pointer flex items-center gap-2"
              :class="{
                'bg-slate-100 dark:bg-slate-600':
                  selectedAgentFilter === agent.id,
              }"
              @click="selectAgent(agent.id)"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="lucide lucide-user-icon lucide-user flex-shrink-0"
              >
                <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2" />
                <circle cx="12" cy="7" r="4" />
              </svg>
              {{ agent.name }}
            </div>
          </div>
        </div>

        <!-- Custom Channel Filter -->
        <div class="relative channel-filter-dropdown">
          <div
            class="px-3 py-1.5 text-[12px] border border-slate-300 dark:border-slate-600 rounded-lg bg-slate-50 dark:bg-slate-800 text-slate-700 dark:text-slate-200 cursor-pointer opacity-50 hover:opacity-100 hover:border-slate-400 dark:hover:border-slate-500 transition-all duration-200 flex items-center justify-between"
            :class="[
              {
                'ring-2 ring-blue-500 border-transparent': showChannelDropdown,
              },
              selectedChannelFilter ? 'min-w-[140px]' : 'w-auto',
            ]"
            @click="showChannelDropdown = !showChannelDropdown"
          >
            <div class="flex items-center gap-2 min-w-0 flex-1">
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
                class="lucide lucide-inbox-icon lucide-inbox flex-shrink-0"
              >
                <polyline points="22 12 16 12 14 15 10 15 8 12 2 12" />
                <path
                  d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"
                />
              </svg>
              <span v-if="selectedChannelFilter" class="truncate">
                {{
                  filterChannels.find(c => c.value === selectedChannelFilter)
                    ?.label || 'Canal não encontrado'
                }}
              </span>
            </div>
            <svg
              v-if="selectedChannelFilter"
              xmlns="http://www.w3.org/2000/svg"
              width="14"
              height="14"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="lucide lucide-chevron-down-icon lucide-chevron-down ml-2 text-black/70 dark:text-slate-400 flex-shrink-0"
            >
              <path d="m6 9 6 6 6-6" />
            </svg>
          </div>
          <div
            v-if="showChannelDropdown"
            class="absolute top-full left-0 mt-1 bg-white dark:bg-slate-700 border border-slate-300 dark:border-slate-600 rounded-lg shadow-lg z-50 min-w-[140px] max-h-48 overflow-y-auto"
          >
            <div
              class="px-3 py-2 text-[12px] text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-600 cursor-pointer first:rounded-t-lg flex items-center gap-2"
              @click="selectChannel('')"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="lucide lucide-inbox-icon lucide-inbox flex-shrink-0"
              >
                <polyline points="22 12 16 12 14 15 10 15 8 12 2 12" />
                <path
                  d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"
                />
              </svg>
              {{ $t('KANBAN.FILTER.ALL_CHANNELS') }}
            </div>
            <div
              v-for="channel in filterChannels"
              :key="channel.value"
              class="px-3 py-2 text-[12px] text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-600 cursor-pointer flex items-center gap-2"
              :class="{
                'bg-slate-100 dark:bg-slate-600':
                  selectedChannelFilter === channel.value,
              }"
              @click="selectChannel(channel.value)"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="lucide lucide-inbox-icon lucide-inbox flex-shrink-0"
              >
                <polyline points="22 12 16 12 14 15 10 15 8 12 2 12" />
                <path
                  d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"
                />
              </svg>
              {{ channel.label }}
            </div>
          </div>
        </div>
      </div>

      <!-- Botão de Mensagem Rápida -->
      <div class="md:block hidden">
        <Button
          type="button"
          variant="outline"
          color="slate"
          size="sm"
          class="group"
          :style="
            isQuickMessageActive
              ? {
                  backgroundColor: '#ff6b35',
                  borderColor: '#ff6b35',
                  color: 'white',
                }
              : {}
          "
          @click="handleQuickMessageClick"
        >
          <template #icon>
            <fluent-icon icon="flame" size="16" />
          </template>
          <span class="text-[12px]">{{ $t('KANBAN.QUICK_CHAT') }}</span>
        </Button>
      </div>

      <div class="bulk-actions-selector md:block hidden">
        <AgentTooltip :text="$t('KANBAN.TOOLTIPS.BULK_ACTIONS')" align="left">
          <div
            class="relative cursor-pointer p-1 hover:bg-slate-100 dark:hover:bg-slate-800 rounded"
            @click="handleBulkActions"
          >
            <svg
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              xmlns="http://www.w3.org/2000/svg"
              aria-hidden="true"
              class="text-slate-500"
            >
              <path d="M16 5H3" />
              <path d="M16 12H3" />
              <path d="M11 19H3" />
              <path d="m15 18 2 2 4-4" />
            </svg>
          </div>
        </AgentTooltip>

        <div v-if="showBulkActions" class="dropdown-menu">
          <div
            v-for="action in filteredBulkActions"
            :key="action.id"
            class="dropdown-item"
            @click="selectBulkAction(action)"
          >
            <fluent-icon
              v-if="
                typeof action.icon === 'string' && action.icon.trim() !== ''
              "
              :icon="action.icon"
              size="16"
              class="mr-2"
            />
            <span>{{ action.label }}</span>
            <span
              v-if="action.id === 'show_hidden'"
              class="ml-2 text-xs px-1.5 rounded-full"
              :class="{
                'bg-woot-500 text-white': showHiddenStages,
                'bg-slate-100 text-slate-600': !showHiddenStages,
              }"
            >
              {{ showHiddenStages ? 'Ativo' : 'Inativo' }}
            </span>
          </div>
        </div>
      </div>

      <AgentTooltip :text="$t('KANBAN.TOOLTIPS.FILTER')" align="left">
        <div
          class="relative cursor-pointer p-1 hover:bg-slate-100 dark:hover:bg-slate-800 rounded"
          @click="handleFilter"
        >
          <svg
            width="18"
            height="18"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            xmlns="http://www.w3.org/2000/svg"
            aria-hidden="true"
            class="text-slate-500"
          >
            <path d="M10 5H3" />
            <path d="M12 19H3" />
            <path d="M14 3v4" />
            <path d="M16 17v4" />
            <path d="M21 12h-9" />
            <path d="M21 19h-5" />
            <path d="M21 5h-7" />
            <path d="M8 10v4" />
            <path d="M8 12H3" />
          </svg>
          <span v-if="activeFiltersCount > 0" class="filter-badge">
            {{ activeFiltersCount }}
          </span>
        </div>
      </AgentTooltip>
      <div class="relative md:block hidden">
        <Button
          variant="solid"
          color="blue"
          size="sm"
          class="kanban-add-item-trigger"
          @click="handleAdd"
        >
          <template #icon>
            <fluent-icon icon="add" size="16" />
          </template>
        </Button>

        <div
          v-if="showAddDropdown"
          class="absolute right-0 top-full mt-1 bg-white dark:bg-slate-900 rounded-md shadow-lg border border-slate-100 dark:border-slate-800 min-w-[200px] z-10"
          style="box-shadow: 0 4px 24px 0 rgba(30, 41, 59, 0.08)"
          @mouseleave="showAddDropdown = false"
          @click.stop
        >
          <div
            class="flex items-center gap-2 px-4 py-2 text-sm text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer rounded-none transition-colors"
            @click="handleNewItem"
          >
            <fluent-icon icon="add" size="16" class="mr-2" />
            <span>{{ t('KANBAN.ADD_ITEM') }}</span>
          </div>
          <div
            class="flex items-center gap-2 px-4 py-2 text-sm text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer rounded-none transition-colors"
          >
            <svg
              class="lightning-icon mr-2"
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                d="M13 3L4 14H12L11 21L20 10H12L13 3Z"
                fill="currentColor"
              />
            </svg>
            <span>Criar com IA</span>
          </div>
        </div>
      </div>
      <div class="settings-selector">
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          :title="
            !userIsAdmin ? 'Apenas administradores podem gerenciar funis' : ''
          "
          @click="handleSettingsClick"
        >
          <template #icon>
            <fluent-icon icon="more-vertical" size="16" />
          </template>
        </Button>

        <div
          v-if="showSettingsDropdown"
          class="absolute right-0 top-full mt-1 bg-white dark:bg-slate-900 rounded-md shadow-lg border border-slate-100 dark:border-slate-800 min-w-[200px] z-10"
          style="box-shadow: 0 4px 24px 0 rgba(30, 41, 59, 0.08)"
          @mouseleave="showSettingsDropdown = false"
        >
          <div
            v-for="option in settingsOptions"
            :key="option.id"
            class="flex items-center gap-2 px-4 py-2 text-sm text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer rounded-none transition-colors"
            @click="handleSettingsOption(option)"
          >
            <fluent-icon
              v-if="
                typeof option.icon === 'string' &&
                option.icon.trim() !== '' &&
                !option.customSvg
              "
              :icon="option.icon"
              size="16"
              class="mr-2"
            />
            <svg
              v-else-if="option.customSvg && option.id === 'offers'"
              xmlns="http://www.w3.org/2000/svg"
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="mr-2"
            >
              <path
                d="M21 10V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l2-1.14"
              />
              <path d="m7.5 4.27 9 5.15" />
              <polyline points="3.29 7 12 12 20.71 7" />
              <line x1="12" x2="12" y1="22" y2="12" />
              <circle cx="18.5" cy="15.5" r="2.5" />
              <path d="M20.27 17.27 22 19" />
            </svg>
            <span>{{ option.label }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Menu móvel para elementos ocultos -->
    <!-- Navbar inferior removida conforme solicitado -->

    <!-- Modal para seleção de visualização -->
    <Modal
      v-model:show="showViewModal"
      :on-close="() => (showViewModal = false)"
      size="tiny"
    >
      <div class="p-4">
        <h3 class="text-lg font-medium mb-4">Selecionar visualização</h3>
        <div class="flex flex-col gap-3">
          <button
            class="flex items-center gap-3 p-3 rounded-lg text-left"
            :class="{
              'bg-woot-50 text-woot-600 dark:bg-woot-900/20 dark:text-woot-300':
                currentView === 'kanban',
              'hover:bg-slate-50 dark:hover:bg-slate-700':
                currentView !== 'kanban',
            }"
            @click="
              emit('switchView', 'kanban');
              showViewModal = false;
            "
          >
            <fluent-icon icon="task" size="20" />
            <div>
              <div class="font-medium">Kanban</div>
              <div class="text-xs text-slate-500 dark:text-slate-400">
                Visualização em quadro
              </div>
            </div>
          </button>

          <button
            class="flex items-center gap-3 p-3 rounded-lg text-left"
            :class="{
              'bg-woot-50 text-woot-600 dark:bg-woot-900/20 dark:text-woot-300':
                currentView === 'list',
              'hover:bg-slate-50 dark:hover:bg-slate-700':
                currentView !== 'list',
            }"
            @click="
              emit('switchView', 'list');
              showViewModal = false;
            "
          >
            <fluent-icon icon="list" size="20" />
            <div>
              <div class="font-medium">Lista</div>
              <div class="text-xs text-slate-500 dark:text-slate-400">
                Lista de itens
              </div>
            </div>
          </button>

          <button
            class="flex items-center gap-3 p-3 rounded-lg text-left"
            :class="{
              'bg-woot-50 text-woot-600 dark:bg-woot-900/20 dark:text-woot-300':
                currentView === 'agenda',
              'hover:bg-slate-50 dark:hover:bg-slate-700':
                currentView !== 'agenda',
            }"
            @click="
              emit('switchView', 'agenda');
              showViewModal = false;
            "
          >
            <fluent-icon icon="calendar" size="20" />
            <div>
              <div class="font-medium">Agenda</div>
              <div class="text-xs text-slate-500 dark:text-slate-400">
                Visualização de agenda
              </div>
            </div>
          </button>
        </div>
      </div>
    </Modal>

    <Modal
      v-model:show="showAddModal"
      :on-close="() => (showAddModal = false)"
      size="large"
    >
      <div class="w-full p-6">
        <h3 class="text-lg font-medium mb-6">
          {{ t('KANBAN.ADD_ITEM') }}
        </h3>
        <KanbanItemForm
          v-if="selectedFunnel"
          :funnel-id="selectedFunnel.id"
          :stage="currentStage"
          @saved="handleItemCreated"
          @close="showAddModal = false"
        />
        <div v-else class="text-center text-red-500">
          {{ t('KANBAN.ERRORS.NO_FUNNEL_SELECTED') }}
        </div>
      </div>
    </Modal>

    <KanbanSettings
      :show="showSettingsModal"
      @close="handleCloseSettings"
      @dragbar-visibility-changed="handleDragbarVisibilityChanged"
    />

    <Modal
      v-model:show="showBulkDeleteModal"
      :on-close="() => (showBulkDeleteModal = false)"
    >
      <BulkDeleteModal
        :items="kanbanItems"
        @close="showBulkDeleteModal = false"
        @confirm="handleBulkDelete"
      />
    </Modal>

    <Modal
      v-model:show="showBulkMoveModal"
      :on-close="() => (showBulkMoveModal = false)"
    >
      <BulkMoveModal
        :items="kanbanItems"
        @close="showBulkMoveModal = false"
        @confirm="handleBulkMove"
      />
    </Modal>

    <Modal
      v-model:show="showBulkAddModal"
      :on-close="() => (showBulkAddModal = false)"
    >
      <BulkAddModal
        :current-stage="currentStage"
        @close="showBulkAddModal = false"
        @items-created="handleBulkItemsCreated"
      />
    </Modal>

    <KanbanFilter
      :show="showFilterModal"
      :current-funnel="selectedFunnel"
      :initial-filters="kanbanFilterInitialFilters"
      size="large"
      @close="showFilterModal = false"
      @apply="handleFilterApply"
      @filter-results="handleFilterResults"
    />

    <!-- AI Modal -->
    <Modal
      v-model:show="showAIModal"
      :on-close="() => (showAIModal = false)"
      size="large"
      class="ai-modal"
      hide-close-button
    >
      <KanbanAI @close="showAIModal = false" />
    </Modal>

    <!-- Modal de compartilhamento -->
    <Modal
      v-model:show="showShareModal"
      :on-close="() => (showShareModal = false)"
      size="tiny"
    >
      <div class="p-4 space-y-4">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-medium">
            {{ t('KANBAN.SHARE.TITLE') }}
          </h3>
        </div>
        <div class="relative">
          <input
            v-model="shareAgentSearch"
            type="text"
            class="w-full px-3 py-2 border rounded-lg pr-8"
            placeholder="Buscar agentes..."
          />
          <fluent-icon
            icon="search"
            size="16"
            class="absolute right-3 top-1/2 transform -translate-y-1/2 text-slate-400"
          />
        </div>
        <div class="max-h-[300px] overflow-y-auto space-y-2">
          <div
            v-if="loadingShareAgents"
            class="text-center text-slate-400 py-4"
          >
            Carregando agentes...
          </div>
          <div
            v-else-if="filteredShareAgents.length === 0"
            class="text-center text-slate-400 py-4"
          >
            Nenhum agente encontrado
          </div>
          <div
            v-for="agent in filteredShareAgents"
            :key="agent.id"
            class="flex items-center gap-3 p-2 hover:bg-slate-50 dark:hover:bg-slate-800 rounded-lg cursor-pointer"
            :class="{
              'bg-woot-50 dark:bg-woot-900/20': isAgentSelected(agent),
            }"
            @click="toggleShareAgent(agent)"
          >
            <Avatar
              :name="agent.name"
              :src="agent.avatar_url"
              :size="32"
              :status="agent.availability_status"
            />
            <div class="flex-1 min-w-0">
              <div class="font-medium text-sm truncate">
                {{ agent.name }}
                <span
                  v-if="isAgentSelected(agent)"
                  class="ml-2 px-2 py-0.5 rounded-full text-xs font-semibold border border-woot-200 bg-woot-50 text-woot-600 align-middle"
                  >Atribuído</span
                >
              </div>
              <div class="text-xs text-slate-500 dark:text-slate-400 truncate">
                {{ agent.email }}
              </div>
            </div>
            <fluent-icon
              v-if="isAgentSelected(agent)"
              icon="checkmark"
              size="16"
              class="text-woot-500"
            />
          </div>
        </div>
      </div>
    </Modal>

    <!-- Modal de Novo Funil -->

    <!-- Modal de Envio de Mensagem -->
    <Modal
      v-model:show="showSendMessageModal"
      :on-close="() => (showSendMessageModal = false)"
      size="medium"
      class="bulk-send-message-modal"
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4">Enviar Mensagens em Massa</h3>
        <BulkSendMessageModal
          :items="[]"
          @close="showSendMessageModal = false"
          @send="handleMessageSent"
        />
      </div>
    </Modal>

    <!-- Renderização condicional da DragBar -->
    <Dragbar
      v-if="dragbarEnabled && isDraggingActive && draggedItem"
      :enabled="dragbarEnabled"
      :dragged-item="draggedItem"
    />
  </header>
</template>

<style lang="scss" scoped>
.kanban-header-custom {
  padding-bottom: 0 !important;
  margin-bottom: 0 !important;
}

.kanban-header {
  position: relative;
  z-index: 10;
  display: flex;
  justify-content: space-between;
  align-items: center;
  /* padding: var(--space-normal); */ // Removido padding
  /* border-bottom: 1px solid var(--color-border); */ // Removido divider

  @apply dark:border-slate-800 flex-wrap;

  @media (max-width: 768px) {
    /* padding: var(--space-small); */ // Removido padding
    gap: var(--space-small);
  }
}

.header-left {
  display: flex;
  align-items: center;
  gap: var(--space-normal);
  min-width: 0;

  @media (max-width: 768px) {
    gap: var(--space-small);
    flex-wrap: wrap;
  }
}

.header-right {
  display: flex;
  align-items: center;
  gap: var(--space-small);

  @media (max-width: 768px) {
    gap: 4px;
  }
}

.search-container {
  @apply flex items-center relative gap-1;

  &.is-active {
    .search-input-wrapper {
      width: auto;
      @apply flex-grow; // Allow wrapper to grow
    }
  }
}

.search-input-wrapper {
  @apply h-8 rounded-lg border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-900;
  @apply flex items-center; // Explicitly make input a flex container to center text
  @apply overflow-hidden transition-all duration-200;
  @apply focus-within:border-woot-500; // Focus style on wrapper
  width: auto; // Allow natural width when visible
  min-width: 200px; // Minimum width when expanded
}

.search-input {
  @apply w-full bg-transparent border-none outline-none ring-0 m-0; // Removed h-full, Added flex, items-center
  @apply flex items-center; // Explicitly make input a flex container to center text
  @apply px-3 text-sm text-slate-800 dark:text-slate-100; // Padding and text styles
  margin-bottom: 0 !important; // Override global margin forcefully

  &:focus {
    @apply outline-none ring-0; // Ensure no focus outline on input itself
  }

  &::placeholder {
    @apply text-slate-500 text-xs; // Just color and size
  }
}

.bulk-actions-selector {
  position: relative;
  display: inline-block;
}

.dropdown-menu {
  position: absolute;
  top: 100%;
  left: 0;
  z-index: 99999;
  min-width: 200px;
  margin-top: 0.25rem;
  padding: 0.25rem 0;
  background: white;
  border: 1px solid #e2e8f0;
  border-radius: 0.5rem;
  box-shadow: 0 4px 24px 0 rgba(30, 41, 59, 0.08);

  @apply dark:bg-slate-800 dark:border-slate-700;
}

.dropdown-item {
  display: flex;
  align-items: center;
  padding: 0.5rem 1rem;
  cursor: pointer;
  border-radius: 0.375rem;
  color: #374151;

  @apply dark:text-slate-100;

  &:hover {
    background: #f9fafb;
    @apply dark:bg-slate-700;
  }
}

.settings-selector {
  position: relative;
  display: inline-block;

  .dropdown-menu {
    right: 0;
    left: auto;
    transform: translateY(4px);
    z-index: 99999;
  }
}

.bulk-actions-selector {
  position: relative;
  display: inline-block;

  .dropdown-menu {
    right: 0;
    left: auto;
    transform: translateY(4px);
    z-index: 99999;
  }
}

.search-results-tags {
  @apply flex items-center gap-1 flex-shrink-0;
}

.search-results-tag {
  @apply flex items-center px-2 py-0.5 text-xs font-medium rounded-full
    bg-woot-500 text-white whitespace-nowrap gap-1;

  &:first-child {
    @apply bg-slate-600;
  }

  .stage-name {
    @apply text-[10px];
  }

  .count-badge {
    @apply bg-white/20 px-1.5 rounded-full text-[10px] min-w-[18px] text-center;
  }
}

.message-templates-btn {
  @apply border border-dashed border-woot-500 text-woot-500 hover:bg-woot-50 
    dark:hover:bg-woot-800/20 transition-colors;

  &:hover {
    @apply border-woot-600 text-woot-600;
  }
}

.add-item-btn {
  @apply bg-woot-500 text-white p-2;

  .mr-1 {
    @apply m-0;
  }
}

.filter-badge {
  @apply absolute -top-1 -right-1 min-w-[16px] h-4 px-1
    flex items-center justify-center
    text-[10px] font-medium
    bg-woot-500 text-white
    rounded-full;
}

// Adicione estilos específicos para selects
select {
  @apply bg-white dark:bg-slate-800 cursor-pointer;
  @apply border border-slate-200 dark:border-slate-700;
  @apply rounded-lg px-3 py-2;
  @apply text-slate-800 dark:text-slate-100;
  @apply hover:border-slate-300 dark:hover:border-slate-600;
  @apply focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500;
  @apply disabled:opacity-50 disabled:cursor-not-allowed;
}

.view-toggle-buttons {
  @apply border border-slate-200 dark:border-slate-700 rounded-lg overflow-hidden;

  .woot-button {
    @apply px-2 py-1.5 border-0 rounded-none;

    &:first-child {
      @apply border-r border-slate-200 dark:border-slate-700;
    }

    &.active {
      @apply bg-slate-100 dark:bg-slate-700 text-woot-500;
    }

    &:hover:not(.active) {
      @apply bg-slate-50 dark:bg-slate-800;
    }
  }
}

.kanban-ai-button {
  @apply flex items-center gap-2 px-3 py-1.5 rounded-lg font-medium text-white text-sm;
  background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
  transition: all 0.2s ease;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
  height: 32px; /* Altura fixa para evitar mudança no hover */

  &:active {
    transform: translateY(0);
  }

  .lightning-icon {
    filter: drop-shadow(0 1px 1px rgba(0, 0, 0, 0.1));
  }

  .ai-button-text {
    display: none;
    transition:
      opacity 0.5s ease,
      visibility 0.5s ease;
    opacity: 0;
    visibility: hidden;
  }

  &:hover .ai-button-text {
    display: inline;
    margin-left: 0.25rem;
    opacity: 1;
    visibility: visible;
  }
}

.ai-modal {
  :deep(.modal__content) {
    @apply w-[85vw] h-[85vh] max-w-[1400px] p-0;
  }
}

.share-button {
  @apply flex items-center px-3 py-1.5 rounded-lg font-medium text-white text-sm;
  background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
  transition: all 0.2s ease;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);

  .share-button-content {
    @apply flex items-center gap-2;
  }

  &:hover {
    filter: brightness(1.1);
  }

  &:active {
    transform: translateY(0);
  }

  .share-icon {
    @apply text-white;
  }

  .share-button-text {
    @apply text-white;
  }
}

.share-button-container {
  @apply flex items-center gap-2;
}

.agents-stack {
  @apply flex items-center;

  .agent-avatar {
    @apply border-2 border-white dark:border-slate-800;
    margin-left: -8px;

    &:first-child {
      margin-left: 0;
    }
  }

  .more-agents {
    @apply flex items-center justify-center
    w-6 h-6 rounded-full
    bg-slate-100 dark:bg-slate-700
    text-xs font-medium
    border-2 border-white dark:border-slate-800
    ml-[-8px];
  }
}

.view-select-btn {
  @apply text-slate-700 dark:text-slate-200 border border-slate-200 dark:border-slate-600;

  &:hover {
    @apply bg-slate-200 dark:bg-slate-600;
  }

  &:active {
    @apply bg-slate-300 dark:bg-slate-500;
  }
}

.view-selector {
  .view-buttons-container {
    display: flex;
    gap: 0.25rem;
    transition: all 0.2s ease;

    .view-button {
      gap: 0.25rem;

      .view-text {
        display: inline;
        transition: all 0.2s ease;
        @apply text-[12px];
      }

      &.active {
        opacity: 1;
        transform: scale(1);
        visibility: visible;
        background-color: rgb(59 130 246);
        border-color: rgb(59 130 246);
        color: white;
      }

      &.inactive {
        opacity: 1;
        transform: scale(1);
        visibility: visible;
      }
    }
  }
}

// Garantir que o FunnelSelector não tenha margin/padding lateral
funnel-selector.md\\:block.hidden {
  margin: 0 !important;
  padding: 0 !important;
}

.kanban-status-badge {
  @apply px-2 py-1 text-xs font-medium rounded-full flex items-center gap-1 transition-colors border border-slate-100 dark:border-slate-800 shadow-sm;
  background: transparent;
  color: #334155;
  outline: none;
  box-shadow: 0 2px 8px 0 rgba(30, 41, 59, 0.04);
  &:hover {
    background: #f1f5f9;
  }
  .button-icon {
    @apply text-slate-500 dark:text-slate-400;
    transition: color 0.2s;
  }
}
.kanban-status-badge--active {
  background: transparent !important;
  color: #334155;
  border: 1px solid #bbf7d0;
  .button-icon {
    color: #16a34a !important;
  }
  &:hover {
    color: #16a34a;
    .button-icon {
      color: #16a34a !important;
    }
  }
}
.kanban-status-badge--active-lost {
  background: transparent !important;
  color: #334155;
  border: 1px solid #fecaca;
  .button-icon {
    color: #dc2626 !important;
  }
  &:hover {
    color: #dc2626;
    .button-icon {
      color: #dc2626 !important;
    }
  }
}
.kanban-status-badge--quick-active {
  background: #f9fafb !important; /* slate-50 para light */
  color: #334155;
  border: 1px solid #fde68a;
  .button-icon {
    color: #eab308 !important;
  }
  &:hover {
    color: #eab308;
    .button-icon {
      color: #eab308 !important;
    }
  }
  @media (prefers-color-scheme: dark) {
    background: #475569 !important; /* slate-600 para dark */
    color: #fff;
    &:hover {
      color: #eab308;
    }
  }
}
.kanban-status-badge--inactive {
  background: transparent !important;
  color: #64748b;
  border: 1px solid #e2e8f0;
  .button-icon {
    color: #64748b;
  }
  &:hover {
    color: #64748b;
    .button-icon {
      color: #64748b;
    }
  }
}

.quick-message-button {
  margin-left: 0.5rem;
}

.bulk-send-message-modal {
  :deep(.modal__overlay) {
    z-index: 9999;
  }

  :deep(.modal__content) {
    z-index: 10000;
  }
}

/* Media query para ocultar view-selector em mobile */
@media (max-width: 767px) {
  .view-selector {
    display: none !important;
  }
}
</style>
