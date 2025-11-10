<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
// import KanbanAPI from '../../../../api/kanban'; // Removed unused import
import KanbanColumn from './KanbanColumn.vue';
import KanbanColumnSkeleton from './KanbanColumnSkeleton.vue';
import KanbanHeader from './KanbanHeader.vue';
import { useStore } from 'vuex';
import KanbanItemForm from './KanbanItemForm.vue';
import Modal from '../../../../components/Modal.vue';
import KanbanItemDetails from './KanbanItemDetails.vue';
import KanbanFilter from './KanbanFilter.vue';
import { emitter } from 'shared/helpers/mitt';

// Emitir evento para navegar para funnels no modo de criação
const handleCreateFunnelClick = () => {
  emit('switchView', 'funnels', { mode: 'create' });
};
import FunnelForm from './FunnelForm.vue';
import Dragbar from './Dragbar.vue';

const props = defineProps({
  currentView: {
    type: String,
    default: 'kanban',
  },
});

const emit = defineEmits(['switchView', 'itemClick']);
const { t } = useI18n();
const store = useStore();
const router = useRouter();

// Estado
const error = computed(() => store.state.kanban.error);
const columns = ref([]);
const showAddModal = ref(false);
const selectedColumn = ref(null);
const selectedFunnel = computed(() => {
  return store.getters['funnel/getSelectedFunnel'];
});

// Estado de loading baseado no store
const isLoading = computed(() => store.state.kanban.loading);

const showDeleteModal = ref(false);
const itemToDelete = ref(null);
const showEditModal = ref(false);
const itemToEdit = ref(null);
const showDetailsModal = ref(false);
const itemToShow = ref(null);
const activeFilters = ref(null);
const showFilterModal = ref(false);
const searchResults = ref(null);
const searchQuery = ref('');
// const mountKey = ref(0); // Removed unused variable
const isUpdating = ref(false);
const showCreateFunnelModal = ref(false);

// New reactive state for global status filters from header
const activeGlobalStatusFilters = ref({ won: true, lost: true });

// New reactive states for dragging
const isDraggingActive = ref(false);
const activeDraggedItem = ref(null);

// Refs for Move Modal (similar to KanbanItemDetails)
const showMoveModal = ref(false);
const itemToMove = ref(null); // To store the item being moved via Dragbar
const moveForm = ref({
  funnel_id: null,
  funnel_stage: null,
});

// New reactive state for expanded column
const expandedColumnId = ref(null);

// Handler for global status filter changes from KanbanHeader
const handleGlobalStatusFilterChange = filters => {
  activeGlobalStatusFilters.value = filters;
};

// Funções
const updateColumns = () => {
  // Obter os estágios do funil selecionado
  const funnel = store.getters['funnel/getSelectedFunnel'];
  if (!funnel?.stages) return;

  // Transformar em array mantendo a ordem original do objeto
  const stagesArray = Object.entries(funnel.stages).map(([id, stage]) => ({
    id,
    title: stage.name,
    color: stage.color,
    description: stage.description,
    position: parseInt(stage.position, 10) || 0,
    // Remover items - cada coluna busca seus próprios itens
  }));

  // Ordenar os estágios por posição
  stagesArray.sort((a, b) => a.position - b.position);

  // Atualizar as colunas com a ordem ordenada por posição
  columns.value = stagesArray;
  showCreateFunnelModal.value = false;
};

// Atualizar colunas quando o funil mudar
watch(
  selectedFunnel,
  newFunnel => {
    if (!newFunnel) return;

    // Garantir que as posições sejam números inteiros
    if (newFunnel.stages) {
      Object.values(newFunnel.stages).forEach(stage => {
        stage.position = parseInt(stage.position, 10) || 0;
      });
    }

    // Atualizar colunas com a ordenação correta
    updateColumns();
  },
  { immediate: true }
);

const handleAdd = columnId => {
  selectedColumn.value = columns.value.find(col => col.id === columnId);
  showAddModal.value = true;
};

const handleDelete = async itemToDeleteParam => {
  try {
    isUpdating.value = true;
    await store.dispatch('kanban/deleteKanbanItem', itemToDeleteParam.id);

    // ✅ NOTIFICAR COLUNAS SOBRE A DELEÇÃO
    emitter.emit('kanbanItemDeleted', { itemId: itemToDeleteParam.id });

    showDeleteModal.value = false;
    itemToDelete.value = null;
  } catch (err) {
    emitter.emit('newToastMessage', {
      message: err.response?.data?.message || t('KANBAN.ERROR_DELETING_ITEM'),
      action: { type: 'error' },
    });
  } finally {
    isUpdating.value = false;
  }
};

const handleDrop = async ({ itemId, columnId, funnelId }) => {
  if (!itemId || !columnId) return;

  // Obter item original - tentar múltiplas fontes
  let originalItem = store.getters['kanban/getItemById'](parseInt(itemId, 10));
  let fromStage = originalItem?.funnel_stage;

  // Se não encontrou no store, tentar buscar da API diretamente
  if (!fromStage) {
    try {
      const response = await KanbanAPI.getItem(parseInt(itemId, 10));
      fromStage = response.data?.funnel_stage;
    } catch (apiError) {
      console.error(`[KanbanTab] Erro ao buscar item da API:`, apiError);
    }
  }

  try {
    isUpdating.value = true;

    // Chamada ao store - o store já gerencia a atualização dos itens
    const updatedItem = await store.dispatch('kanban/moveItemToStage', {
      itemId: parseInt(itemId, 10),
      columnId,
      funnelId,
    });

    // ✅ EMITIR EVENTO DIRETO PARA COLUNAS AFETADAS
    emitter.emit('kanbanItemMoved', {
      itemId: parseInt(itemId, 10),
      fromStage: fromStage,
      toStage: columnId,
      itemData: updatedItem
    });

    // ✅ EMITIR EVENTO PARA ATUALIZAR STATS DAS COLUNAS
    emitter.emit('kanbanItemMovedBetweenStages', {
      itemId: parseInt(itemId, 10),
      fromStage: fromStage,
      toStage: columnId,
      funnelId: funnelId
    });

    // Apenas forçar atualização visual das colunas sem buscar novos dados
    nextTick(() => {
      updateColumns();
    });
  } catch (err) {
    // Exibir mensagem de erro específica se for erro de checklist obrigatório
    const errorMessage = err.response?.data?.error || err.response?.data?.message || t('KANBAN.ERROR_MOVING_ITEM');
    
    emitter.emit('newToastMessage', {
      message: errorMessage,
      action: { type: 'error' },
    });
  } finally {
    isUpdating.value = false;

    // ✅ ADICIONADO: Garantir que a Dragbar seja ocultada após o drop
    // Use nextTick para garantir que seja executado após outras operações DOM
    nextTick(() => {
      isDraggingActive.value = false;
      activeDraggedItem.value = null;
    });
  }
};

const handleSettings = () => {
  // TODO: Implementar configurações do Kanban
  emitter.emit('newToastMessage', {
    message: t('KANBAN.SETTINGS_NOT_IMPLEMENTED'),
    action: { type: 'info' },
  });
};

const handleItemCreated = async item => {
  if (!item) return;
  showAddModal.value = false;
  selectedColumn.value = null;

  // Disparar evento global para notificar criação de item
  emitter.emit('kanbanItemCreated', item);
};

const handleSearch = query => {
  searchQuery.value = query;
};

const handleSearchResults = results => {
  searchResults.value = results;
};

const handleFilterClose = () => {
  showFilterModal.value = false;

  // Remover recarregamento de itens - cada coluna gerencia seus próprios itens
};

const handleFilter = filters => {
  console.log('[KanbanTab] handleFilter - Filtros recebidos:', filters)
  // Verificação defensiva: se filters for null ou undefined, use um objeto vazio
  activeFilters.value = filters || {};
  console.log('[KanbanTab] handleFilter - activeFilters atualizado:', activeFilters.value)
};

const handleEdit = item => {
  itemToEdit.value = item;
  showEditModal.value = true;
};

const handleItemClick = item => {
  emit('itemClick', item);
};

const handleEditFromDetails = item => {
  showDetailsModal.value = false;
  handleEdit(item);
};

const handleDetailsUpdate = () => {
  // No need to emit 'forceUpdate' here
};

const handleItemEdited = async item => {
  if (!item) return;
  showEditModal.value = false;
  itemToEdit.value = null;

  // Forçar atualização das colunas para refletir mudanças
  nextTick(() => {
    updateColumns();
  });

  // Disparar evento global para notificar outras partes do sistema
  emitter.emit('kanbanItemUpdated', item);
};

// Handler for FunnelForm save
const handleFunnelCreated = savedFunnel => {
  if (savedFunnel) {
    // Optionally dispatch action to update funnel list or select the new one
    store.dispatch('funnel/fetchFunnels').then(() => {
      store.dispatch('funnel/setSelectedFunnel', savedFunnel.id);
    });
  }
  showCreateFunnelModal.value = false;
};

// New handlers for drag events
const handleItemDragStart = item => {
  isDraggingActive.value = true;
  activeDraggedItem.value = item;
};

const handleItemDragEnd = () => {
  // Ensure Dragbar is hidden when any drag operation ends
  // Use nextTick to ensure this update happens after other potential state changes
  nextTick(() => {
    isDraggingActive.value = false;
    activeDraggedItem.value = null;
  });
};

// Handler for Dragbar actions
const handleDragbarQuickAction = async ({ actionId, item }) => {
  isDraggingActive.value = false;
  activeDraggedItem.value = null;
  // Potentially close dragbar after action for a better UX

  if (!item) {
    emitter.emit('newToastMessage', {
      message: t('KANBAN.ERRORS.INVALID_ITEM_FOR_ACTION'),
      action: { type: 'error' },
    });
    return;
  }

  switch (actionId) {
    case 'chat':
      if (
        item.item_details?.conversation?.display_id &&
        item.item_details?.conversation?.account_id &&
        item.item_details?.conversation?.inbox_id
      ) {
        router.push({
          name: 'inbox_conversation',
          params: {
            accountId: item.item_details.conversation.account_id,
            inboxId: item.item_details.conversation.inbox_id,
            conversation_id: item.item_details.conversation.display_id,
          },
        });
      } else {
        emitter.emit('newToastMessage', {
          message: t('KANBAN.ERRORS.NO_CONVERSATION_ASSOCIATED'),
          action: { type: 'warning' },
        });
      }
      break;
    case 'duplicate':
      try {
        const originalDetails = item.item_details || {};
        const newItemData = {
          ...item, // Spread original item data, ensure this is the correct structure
          id: undefined, // API will assign new ID
          title: `${originalDetails.title || 'Item'} (DragBar Copy)`,
          // Preserve stage and funnel, adjust position as needed or let backend handle
          funnel_id: item.funnel_id,
          funnel_stage_id: item.funnel_stage, // Ensure this is the stage ID not the object
          item_details: {
            ...originalDetails,
            title: `${originalDetails.title || 'Item'} (DragBar Copy)`,
            // Clear or adjust any instance-specific details like conversation_id if necessary
            conversation_id: null,
            conversation: null,
          },
        };
        // Remove fields that should not be sent for creation if they exist at root
        delete newItemData.created_at;
        delete newItemData.updated_at;
        delete newItemData.stage_entered_at;
        delete newItemData.conversation_display_id; // if it exists

        await store.dispatch('kanban/createKanbanItem', newItemData);
        emitter.emit('newToastMessage', {
          message: t('KANBAN.SUCCESS_DUPLICATING_ITEM', {
            title: newItemData.title,
          }),
          action: { type: 'success' },
        });
        // Items will be refetched by the store action or a watcher
      } catch (err) {
        emitter.emit('newToastMessage', {
          message:
            err.response?.data?.message || t('KANBAN.ERROR_DUPLICATING_ITEM'),
          action: { type: 'error' },
        });
      }
      break;
    case 'move':
      // Open the move modal for the item from Dragbar
      itemToMove.value = item;
      moveForm.value.funnel_id = item.funnel_id;
      moveForm.value.funnel_stage = item.funnel_stage;
      showMoveModal.value = true;
      break;
    default:
      emitter.emit('newToastMessage', {
        message: t('KANBAN.ERRORS.UNKNOWN_ACTION', { action: actionId }),
        action: { type: 'warning' },
      });
  }
};

// Computed
const userHasAccess = computed(() => {
  const currentUser = store.getters.getCurrentUser;
  const currentFunnel = store.getters['funnel/getSelectedFunnel'];

  if (!currentFunnel || !currentUser) return false;
  if (currentUser.role === 'administrator') return true;

  return currentFunnel.settings?.agents?.some(
    agent => agent.id === currentUser.id
  );
});

// Computed to get funnels (similar to KanbanItemDetails)
const funnels = computed(() => store.getters['funnel/getFunnels'] || []);

// Computed for available stages in Move Modal (similar to KanbanItemDetails)
const availableStagesForMove = computed(() => {
  const funnel = funnels.value.find(
    f => String(f.id) === String(moveForm.value.funnel_id)
  );
  if (!funnel?.stages) return [];
  return Object.entries(funnel.stages)
    .map(([id, stage]) => ({
      id,
      name: stage.name,
      position: stage.position,
    }))
    .sort((a, b) => a.position - b.position);
});

// Watch to reset stage when funnel changes in Move Modal (similar to KanbanItemDetails)
watch(
  () => moveForm.value.funnel_id,
  newFunnelId => {
    const funnel = funnels.value.find(
      f => String(f.id) === String(newFunnelId)
    );
    const firstStage = funnel && Object.keys(funnel.stages)[0];
    moveForm.value.funnel_stage = firstStage || '';
  }
);

// Method to handle actual item move from Modal (similar to KanbanItemDetails)
const handleMoveItemFromModal = async () => {
  if (!itemToMove.value) return;

  try {
    const payload = {
      ...itemToMove.value,
      funnel_id: moveForm.value.funnel_id,
      funnel_stage: moveForm.value.funnel_stage,
    };

    // Dispatch action to update item (or use your existing moveItemToStage if applicable)
    await store.dispatch('kanban/moveItemToStage', {
      itemId: itemToMove.value.id,
      columnId: moveForm.value.funnel_stage,
      funnelId: moveForm.value.funnel_id,
    });

    showMoveModal.value = false;
    itemToMove.value = null;
    emitter.emit('newToastMessage', {
      message: t('KANBAN.SUCCESS_MOVING_ITEM'),
      action: { type: 'success' },
    });
    // Buscar o objeto funil antes de setar como selecionado
    const funnelsList = store.getters['funnel/getFunnels'];
    const targetFunnel = funnelsList.find(
      f => String(f.id) === String(moveForm.value.funnel_id)
    );
    if (targetFunnel) {
      await store.dispatch('funnel/setSelectedFunnel', targetFunnel);
    }
  } catch (err) {
    // Exibir mensagem de erro específica se for erro de checklist obrigatório
    const errorMessage = err.response?.data?.error || err.response?.data?.message || t('KANBAN.ERROR_MOVING_ITEM');
    
    emitter.emit('newToastMessage', {
      message: errorMessage,
      action: { type: 'error' },
    });
  }
};

// Computed para filtrar os itens baseado na busca e nos filtros
const filteredColumns = computed(() => {
  // Retornar apenas as colunas - cada coluna gerencia seus próprios itens
  return [...columns.value];
});

// Computed para calcular os resultados da busca e filtros
const filteredResults = computed(() => {
  const results = {
    total: 0,
    stages: {},
  };

  // Obter todos os itens do store
  const allItems = store.getters['kanban/getKanbanItems'] || [];

  // Aplicar filtros
  let filteredItems = [...allItems];

  // Aplicar filtros ativos se existirem
  if (activeFilters.value) {
    filteredItems = filteredItems.filter(item => {
      if (!item || !item.item_details) return false;

      // Filter by priority
      if (
        activeFilters.value.priority &&
        activeFilters.value.priority.length > 0
      ) {
        const itemPriority = item.item_details?.priority || 'none';
        if (!activeFilters.value.priority.includes(itemPriority)) return false;
      }

      // Filter by value
      if (
        activeFilters.value.value &&
        (activeFilters.value.value.min !== undefined ||
          activeFilters.value.value.max !== undefined)
      ) {
        const itemValue = parseFloat(item.item_details?.value) || 0;
        const min = activeFilters.value.value.min;
        const max = activeFilters.value.value.max;

        if (min !== undefined && min !== null && itemValue < min) return false;
        if (max !== undefined && max !== null && itemValue > max) return false;
      }

      // Filter by agent
      if (activeFilters.value.agent_id) {
        const itemAgentId =
          item.assigned_agent_id ||
          item.assignee_id ||
          (item.item_details && item.item_details.agent_id) ||
          (item.meta && item.meta.agent_id) ||
          null;

        if (activeFilters.value.agent_id === -1) {
          // "Não atribuído" - item deve não ter agente
          if (itemAgentId !== null) return false;
        } else if (itemAgentId != activeFilters.value.agent_id) {
          return false;
        }
      }

      // Filter by date
      if (activeFilters.value.date) {
        const itemDate = item.created_at || item.item_details?.created_at;
        if (itemDate) {
          const itemDateTime = new Date(itemDate);
          const startDate = activeFilters.value.date.start ? new Date(activeFilters.value.date.start) : null;
          const endDate = activeFilters.value.date.end ? new Date(activeFilters.value.date.end) : null;

          if (startDate && itemDateTime < startDate) return false;
          if (endDate && itemDateTime > endDate) return false;
        }
      }

      return true;
    });
  }

  // Aplicar filtros globais de status (won/lost)
  if (activeGlobalStatusFilters.value) {
    filteredItems = filteredItems.filter(item => {
      if (!item || !item.item_details) return true; // Se não tem dados, manter

      const itemStatus = item.item_details?.status?.toLowerCase();

      // Se filtro 'won' está desabilitado e item é 'won', remover
      if (!activeGlobalStatusFilters.value.won && itemStatus === 'won') {
        return false;
      }

      // Se filtro 'lost' está desabilitado e item é 'lost', remover
      if (!activeGlobalStatusFilters.value.lost && itemStatus === 'lost') {
        return false;
      }

      return true;
    });
  }

  // Aplicar filtro de busca se existir
  if (searchQuery.value && searchQuery.value.trim()) {
    const query = searchQuery.value.toLowerCase().trim();

    filteredItems = filteredItems.filter(item => {
      if (!item || !item.item_details) return false;

      const title = (item.item_details.title || '').toLowerCase();
      const description = (item.item_details.description || '').toLowerCase();
      const customerName = (item.item_details.customer_name || '').toLowerCase();
      const customerEmail = (item.item_details.customer_email || '').toLowerCase();

      return title.includes(query) ||
             description.includes(query) ||
             customerName.includes(query) ||
             customerEmail.includes(query);
    });
  }

  // Contar itens por estágio
  filteredItems.forEach(item => {
    const stageId = item.funnel_stage;
    const column = columns.value.find(col => col.id === stageId);

    if (column) {
      const stageName = column.title;
      results.stages[stageName] = (results.stages[stageName] || 0) + 1;
      results.total += 1;
    }
  });

  return results;
});

// Computed para depuração da ordenação final das colunas
const columnsOrderDebug = computed(() => {
  // Log para debugar a ordem final das colunas
  return true;
});

const handleExpandColumn = columnId => {
  expandedColumnId.value = columnId;
};
const handleCloseExpanded = () => {
  expandedColumnId.value = null;
};
</script>

<template>
  <div class="flex flex-col h-full bg-white dark:bg-slate-900">
    <KanbanHeader
      :current-view="currentView"
      :current-stage="selectedColumn?.id"
      :search-results="searchResults"
      :columns="filteredColumns"
      :active-filters="activeFilters"
      :kanban-items="[]"
      :is-dragging-active="isDraggingActive"
      :dragged-item="activeDraggedItem"
      @openFilterModal="showFilterModal = true"
      @filterApplied="handleFilter"
      @globalFilterChange="handleFilter"
      @settings="handleSettings"
      @itemCreated="handleItemCreated"
      @search="handleSearch"
      @searchResults="handleSearchResults"
      @switchView="view => emit('switchView', view)"
      @globalStatusFilterChange="handleGlobalStatusFilterChange"
    />

    <div v-if="isLoading" class="flex-1 overflow-x-auto kanban-columns">
      <div class="flex h-full p-4 space-x-4">
        <KanbanColumnSkeleton v-for="i in 4" :key="`skeleton-${i}`" />
      </div>
    </div>

    <div
      v-else-if="error && error !== 'Nenhum funil selecionado'"
      class="flex justify-center items-center flex-1 text-ruby-500"
    >
      {{ error }}
    </div>

    <div
      v-else-if="!selectedFunnel"
      class="flex flex-col items-center justify-center flex-1 p-4 sm:p-8 text-center"
    >
      <div class="max-w-2xl w-full space-y-6">
        <!-- Card principal -->
        <div class="bg-white dark:bg-slate-900 rounded-xl border border-slate-100 dark:border-slate-800 shadow-lg hover:shadow-xl transition-all duration-300 p-8 relative overflow-hidden">
          <!-- Gradiente de fundo sutil -->
          <div class="absolute inset-0 bg-gradient-to-br from-woot-50/20 via-transparent to-woot-100/10 dark:from-woot-900/5 dark:via-transparent dark:to-woot-800/5 pointer-events-none"></div>

          <div class="relative z-10">
            <!-- Ícone principal -->
            <div class="flex justify-center mb-6">
              <div class="w-20 h-20 bg-gradient-to-br from-woot-500 to-woot-600 dark:from-woot-600 dark:to-woot-700 rounded-2xl flex items-center justify-center shadow-xl transform hover:scale-105 transition-transform duration-200">
                <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-white">
                  <rect width="20" height="14" x="2" y="3" rx="2"/>
                  <line x1="8" x2="16" y1="21" y2="21"/>
                  <line x1="12" x2="12" y1="17" y2="21"/>
                </svg>
              </div>
            </div>

            <!-- Título principal -->
            <h3 class="text-2xl font-bold text-slate-900 dark:text-slate-100 mb-4 leading-tight">
              {{ t('KANBAN.FUNNELS.FORM.CREATE_FIRST') }}
            </h3>

            <!-- Descrição -->
            <p class="text-slate-600 dark:text-slate-400 mb-8 leading-relaxed text-base max-w-lg mx-auto">
              {{ t('KANBAN.FUNNELS.FORM.CREATE_FIRST_MESSAGE') }}
            </p>

            <!-- Dica rápida integrada -->
            <div class="bg-gradient-to-r from-slate-50/80 to-slate-100/80 dark:from-slate-800/50 dark:to-slate-700/50 rounded-xl border border-slate-200/60 dark:border-slate-600/60 p-4 mb-8 shadow-sm hover:shadow-md transition-shadow">
              <div class="flex items-start gap-3">
                <div class="w-8 h-8 bg-gradient-to-br from-woot-100 to-woot-200 dark:from-woot-800 dark:to-woot-700 rounded-lg flex items-center justify-center flex-shrink-0 mt-0.5">
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-woot-600 dark:text-woot-300">
                    <path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.8 1.2 1.5 1.5 2.5"/>
                    <path d="M9 18h6"/>
                    <path d="M10 22h4"/>
                  </svg>
                </div>
                <div class="flex-1 text-left">
                  <h4 class="text-sm font-semibold text-slate-900 dark:text-slate-100 mb-1">
                    {{ t('KANBAN.FUNNELS.FORM.TIP.TITLE') }}
                  </h4>
                  <p class="text-sm text-slate-600 dark:text-slate-400 leading-relaxed">
                    {{ t('KANBAN.FUNNELS.FORM.TIP.DESCRIPTION') }}
                  </p>
                </div>
              </div>
            </div>

            <!-- Botão principal -->
            <button
              class="w-full bg-gradient-to-r from-woot-500 to-woot-600 hover:from-woot-600 hover:to-woot-700 text-white font-semibold py-4 px-6 rounded-xl transition-all duration-200 shadow-lg hover:shadow-xl hover:scale-[1.02] focus:outline-none focus:ring-2 focus:ring-woot-500 focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-slate-900 flex items-center justify-center gap-3 group"
              @click="handleCreateFunnelClick"
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="transition-transform group-hover:scale-110">
                <path d="M5 12h14"/>
                <path d="M12 5v14"/>
              </svg>
              <span>{{ t('KANBAN.FUNNELS.FORM.CREATE_BUTTON') }}</span>
            </button>
          </div>
        </div>

      </div>
    </div>

    <div
      v-else-if="!userHasAccess"
      class="flex flex-col items-center justify-center flex-1 p-8 text-center"
    >
      <div class="w-16 h-16 mb-4 text-slate-400">
        <fluent-icon icon="lock-closed" size="64" />
      </div>
      <h3 class="text-xl font-medium text-slate-700 dark:text-slate-300 mb-2">
        {{ t('KANBAN.ACCESS_RESTRICTED') }}
      </h3>
      <p class="text-sm text-slate-600 dark:text-slate-400 max-w-md">
        {{ t('KANBAN.ACCESS_RESTRICTED_MESSAGE') }}
      </p>
    </div>

    <div v-else class="flex-1 overflow-x-auto kanban-columns">
      <div
        v-if="isUpdating"
        class="absolute top-2 right-2 flex items-center text-sm text-slate-500"
      >
        <span class="loading-spinner-small mr-2" />
        {{ t('KANBAN.UPDATING') }}
      </div>

      <div class="flex h-full p-4 space-x-4">
        <!-- Debug helper hidden -->
        <div v-if="columnsOrderDebug" class="hidden" />

        <template v-if="expandedColumnId">
          <KanbanColumn
            v-for="column in filteredColumns.filter(
              col => col.id === expandedColumnId
            )"
            :key="column.id"
            :id="column.id"
            :title="column.title"
            :color="column.color"
            :total-columns="filteredColumns.length"
            :is-expanded="true"
            :search-query="searchQuery"
            :search-results="searchResults"
            :active-filters="activeFilters"
            :global-status-filters="activeGlobalStatusFilters"
            @add="handleAdd"
            @edit="handleEdit"
            @delete="handleDelete"
            @drop="handleDrop"
            @item-click="handleItemClick"
            @itemDragstart="handleItemDragStart"
            @itemDragend="handleItemDragEnd"
            @expand="handleExpandColumn"
            @closeExpanded="handleCloseExpanded"
          />
        </template>
        <template v-else>
          <KanbanColumn
            v-for="column in filteredColumns
              .slice()
              .sort((a, b) => a.position - b.position)"
            :key="column.id"
            :id="column.id"
            :title="column.title"
            :color="column.color"
            :total-columns="filteredColumns.length"
            :is-expanded="false"
            :search-query="searchQuery"
            :search-results="searchResults"
            :active-filters="activeFilters"
            :global-status-filters="activeGlobalStatusFilters"
            @add="handleAdd"
            @edit="handleEdit"
            @delete="handleDelete"
            @drop="handleDrop"
            @item-click="handleItemClick"
            @itemDragstart="handleItemDragStart"
            @itemDragend="handleItemDragEnd"
            @expand="handleExpandColumn"
            @closeExpanded="handleCloseExpanded"
          />
        </template>
      </div>
    </div>

    <!-- Modais -->
    <Modal
      v-model:show="showAddModal"
      size="full-width"
      :on-close="() => (showAddModal = false)"
    >
      <div class="p-6">
        <h3 class="text-lg font-medium">
          {{ t('KANBAN.ADD_ITEM') }}
        </h3>
        <KanbanItemForm
          v-if="selectedColumn && selectedFunnel"
          :funnel-id="selectedFunnel.id"
          :stage="selectedColumn.id"
          :position="selectedColumn.position"
          @saved="handleItemCreated"
          @close="showAddModal = false"
        />
        <div v-else class="text-center text-red-500">
          {{ t('KANBAN.ERRORS.NO_FUNNEL_SELECTED') }}
        </div>
      </div>
    </Modal>

    <Modal
      v-model:show="showDeleteModal"
      :on-close="
        () => {
          showDeleteModal = false;
          itemToDelete = null;
        }
      "
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4">
          {{ t('KANBAN.DELETE_CONFIRMATION.TITLE') }}
        </h3>
        <p class="text-sm text-slate-600 dark:text-slate-400 mb-6">
          {{
            t('KANBAN.DELETE_CONFIRMATION.MESSAGE', {
              item: itemToDelete?.title,
            })
          }}
        </p>
        <div class="flex justify-end space-x-2">
          <woot-button
            variant="clear"
            color-scheme="secondary"
            @click="showDeleteModal = false"
          >
            {{ t('KANBAN.CANCEL') }}
          </woot-button>
          <woot-button
            variant="solid"
            color-scheme="alert"
            @click="handleDelete(itemToDelete)"
          >
            {{ t('KANBAN.DELETE') }}
          </woot-button>
        </div>
      </div>
    </Modal>

    <Modal
      v-model:show="showEditModal"
      size="full-width"
      :on-close="
        () => {
          showEditModal = false;
          itemToEdit = null;
        }
      "
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4">
          {{ t('KANBAN.FORM.EDIT_ITEM') }}
        </h3>
        <KanbanItemForm
          v-if="itemToEdit && selectedFunnel"
          :funnel-id="selectedFunnel.id"
          :stage="itemToEdit.funnel_stage"
          :position="itemToEdit.position"
          :initial-data="itemToEdit"
          is-editing
          @saved="handleItemEdited"
          @close="showEditModal = false"
        />
      </div>
    </Modal>

    <Modal
      v-model:show="showDetailsModal"
      size="full-width"
      :on-close="
        () => {
          showDetailsModal = false;
          itemToShow = null;
          handleDetailsUpdate();
        }
      "
    >
      <KanbanItemDetails
        v-if="itemToShow"
        :item="itemToShow"
        @close="
          () => {
            showDetailsModal = false;
            itemToShow = null;
            handleDetailsUpdate();
          }
        "
        @edit="handleEditFromDetails"
        @item-updated="handleDetailsUpdate"
      />
    </Modal>

    <!-- Modal for Moving Item (from Dragbar) -->
    <Modal
      v-if="showMoveModal"
      :show="showMoveModal"
      @close="showMoveModal = false"
    >
      <div class="p-4 space-y-4">
        <h3 class="text-lg font-medium text-slate-900 dark:text-slate-100">
          {{ t('KANBAN.BULK_ACTIONS.MOVE.TITLE') }} -
          {{ itemToMove?.item_details?.title || itemToMove?.title }}
        </h3>

        <!-- Funnel Selector -->
        <div class="space-y-2">
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300"
          >
            {{ t('KANBAN.FORM.FUNNEL.LABEL') }}
          </label>
          <select
            v-model="moveForm.funnel_id"
            class="w-full h-10 px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
          >
            <option
              v-for="funnel in funnels"
              :key="funnel.id"
              :value="funnel.id"
            >
              {{ funnel.name }}
            </option>
          </select>
        </div>

        <!-- Stage Selector -->
        <div class="space-y-2">
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300"
          >
            {{ t('KANBAN.FORM.STAGE.LABEL') }}
          </label>
          <select
            v-model="moveForm.funnel_stage"
            class="w-full h-10 px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
          >
            <option
              v-for="stage in availableStagesForMove"
              :key="stage.id"
              :value="stage.id"
            >
              {{ stage.name }}
            </option>
          </select>
        </div>

        <!-- Buttons -->
        <div class="flex justify-end gap-2 mt-4">
          <button
            class="px-4 py-2 text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
            @click="showMoveModal = false"
          >
            {{ t('KANBAN.CANCEL') }}
          </button>
          <button
            class="px-4 py-2 text-sm text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors"
            @click="handleMoveItemFromModal"
          >
            {{ t('KANBAN.MOVE') }}
          </button>
        </div>
      </div>
    </Modal>

    <!-- Modal for Creating Funnel -->
    <Modal
      v-model:show="showCreateFunnelModal"
      size="large"
      :on-close="() => (showCreateFunnelModal = false)"
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-6">
          {{ t('KANBAN.FUNNELS.FORM.CREATE.TITLE') }}
        </h3>
        <FunnelForm
          @saved="handleFunnelCreated"
          @close="showCreateFunnelModal = false"
        />
      </div>
    </Modal>

    <KanbanFilter
      :show="showFilterModal"
      :columns="columns"
      :filtered-results="filteredResults"
      :current-funnel="store.getters['funnel/getSelectedFunnel']"
      @close="handleFilterClose"
      @apply="handleFilter"
    />
  </div>
</template>

<style scoped>
.flex-1 {
  min-height: 0;
}

.kanban-columns {
  scrollbar-width: thin;
  scrollbar-color: var(--color-woot) var(--color-background-light);
}

.kanban-columns::-webkit-scrollbar {
  height: 8px;
  background: transparent;
}

.kanban-columns::-webkit-scrollbar-track {
  background: var(--color-background-light);
  border-radius: 4px;
}

.kanban-columns::-webkit-scrollbar-thumb {
  background: var(--color-woot);
  border-radius: 4px;
  opacity: 0.8;
}

.kanban-columns::-webkit-scrollbar-thumb:hover {
  opacity: 1;
}

.loading-spinner {
  width: 40px;
  height: 40px;
  border: 3px solid #f3f3f3;
  border-top: 3px solid #3498db;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

.loading-spinner-small {
  width: 16px;
  height: 16px;
  border: 2px solid #f3f3f3;
  border-top: 2px solid #3498db;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(360deg);
  }
}

:root {
  --color-background-light: #f1f5f9;
}

.dark {
  --color-background-light: #1e293b;
}
</style>
