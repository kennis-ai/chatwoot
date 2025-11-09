<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import KanbanHeader from './KanbanHeader.vue';
import KanbanAPI from '../../../../api/kanban';
import Modal from 'dashboard/components/Modal.vue';
import CustomContextMenu from 'dashboard/components/ui/CustomContextMenu.vue';
import SendMessageTemplate from './SendMessageTemplate.vue';
import KanbanItemForm from './KanbanItemForm.vue';

const props = defineProps({
  currentView: {
    type: String,
    default: 'list',
  },
  // A propriedade 'kanbanItems' não é mais necessária, mas a mantive para evitar erros se ainda for passada
  kanbanItems: {
    type: Array,
    required: false,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  labelsMap: {
    type: Object,
    default: () => ({}),
  },
});
const emit = defineEmits([
  'switch-view',
  'itemClick',
  'force-update',
  'itemsUpdated',
]);
const { t } = useI18n();
const store = useStore();
const router = useRouter();
const isLoading = ref(false);
const deals = ref([]);
const errorMessage = ref(null);
const searchQuery = ref('');
const activeFilters = ref(null);

// Estado para itens do Kanban (similar ao KanbanColumn.vue)
const kanbanItems = ref([]);
const isLoadingItems = ref(false);
const currentPage = ref(1);
const hasMoreItems = ref(true);
const isLoadingMore = ref(false);

const selectedFunnel = computed(
  () => store.getters['funnel/getSelectedFunnel']
);

// Removido: kanbanItems agora é um ref que buscamos diretamente da API
// const kanbanItems = computed(() => store.getters['kanban/getKanbanItems']);
// const isKanbanLoading = computed(() => store.state.kanban.loading);

const showDeleteModal = ref(false);
const showContextMenu = ref(false);
const showSendMessageModal = ref(false);
const contextMenuPosition = ref({ x: 0, y: 0 });
const itemToDelete = ref(null);
const selectedDeal = ref(null);
const isDeleting = ref(false);

const expandedStages = ref(new Set());
const showEditModal = ref(false);
const itemToEdit = ref(null);

const funnelsCache = computed(() => {
  const allFunnels = store.getters['funnel/getFunnels'] || [];
  const cache = {};
  allFunnels.forEach(funnel => {
    cache[funnel.id] = funnel;
  });
  return cache;
});

const processDeals = () => {
  try {
    const currentFunnel = selectedFunnel.value;
    if (!currentFunnel?.id) {
      errorMessage.value = 'Nenhum funil selecionado';
      deals.value = [];
      return;
    }

    const itemsToProcess = kanbanItems.value;
    if (!Array.isArray(itemsToProcess)) {
      console.error('kanbanItems não é um array. Não é possível processar.');
      deals.value = [];
      return;
    }

    const currentFunnelItems = itemsToProcess.filter(
      item => String(item.funnel_id) === String(currentFunnel.id)
    );

    console.log(
      'Items encontrados para o funil atual:',
      currentFunnelItems.length
    );

    deals.value = currentFunnelItems.map(item => {
      const stageName = currentFunnel.stages[item.funnel_stage]?.name || '';
      const stageColor =
        currentFunnel.stages[item.funnel_stage]?.color || '#64748B';

      return {
        id: item.id,
        title: item.item_details?.title || '',
        description: item.item_details?.description || '',
        priority: item.item_details?.priority || 'none',
        assignee: item.item_details?.agent || null,
        value: item.item_details?.value || 0,
        stage: item.funnel_stage,
        stageName,
        stageColor,
        createdAt: new Date(item.created_at).toLocaleDateString(),
        item_details: item.item_details,
        funnel_id: String(item.funnel_id),
      };
    });

    console.log('Deals processados:', deals.value.length);
  } catch (err) {
    console.error('Erro ao processar deals:', err);
    errorMessage.value = err.message;
  }
};

// Função para buscar itens do Kanban (similar ao KanbanColumn.vue)
const fetchKanbanItems = async (page = 1, reset = false) => {
  if (isLoadingItems.value) return;

  try {
    isLoadingItems.value = true;
    if (page > 1) {
      isLoadingMore.value = true;
    }

    console.log(`[ListTab] Buscando itens do funil, página ${page}`);

    // Buscar todos os itens do funil atual
    const response = await KanbanAPI.getItems(selectedFunnel.value?.id);
    const items = response.data.items || response.data;

    console.log(`[ListTab] API retornou ${items.length} itens`);

    if (reset || page === 1) {
      kanbanItems.value = items;
      currentPage.value = 1;
    } else {
      kanbanItems.value = [...kanbanItems.value, ...items];
    }

    currentPage.value = page;
    hasMoreItems.value = items.length === 50; // Assumindo que 50 é o limite padrão

    console.log(`[ListTab] Agora tem ${kanbanItems.value.length} itens`);
  } catch (error) {
    console.error('[ListTab] Erro ao buscar itens:', error);
  } finally {
    isLoadingItems.value = false;
    isLoadingMore.value = false;
  }
};

const fetchData = async () => {
  isLoading.value = true;
  if (selectedFunnel.value) {
    await fetchKanbanItems(1, true);
  }
  isLoading.value = false;
};

watch(
  () => kanbanItems.value,
  () => processDeals()
);

watch(
  () => selectedFunnel.value,
  () => processDeals()
);

watch(
  () => store.getters['funnel/getFunnels'],
  () => processDeals()
);

// Watcher para mudanças no funil selecionado (similar ao KanbanColumn.vue)
watch(
  selectedFunnel,
  async (newFunnel, oldFunnel) => {
    if (newFunnel && newFunnel.id !== oldFunnel?.id) {
      console.log(
        `[ListTab] Funil mudou para ${newFunnel.id}, recarregando itens`
      );
      await fetchKanbanItems(1, true);
    }
  },
  { immediate: false } // Não executar imediatamente, deixar o onMounted fazer isso
);

onMounted(() => {
  if (selectedFunnel.value) {
    fetchData();
  }
});

const filteredDeals = computed(() => {
  let filtered = deals.value;

  if (searchQuery.value) {
    const query = searchQuery.value.toLowerCase();
    filtered = filtered.filter(
      deal =>
        deal.title.toLowerCase().includes(query) ||
        deal.description.toLowerCase().includes(query) ||
        deal.assignee?.name.toLowerCase().includes(query)
    );
  }

  if (activeFilters.value) {
    const filters = activeFilters.value;

    filtered = filtered.filter(deal => {
      let matches = true;
      if (filters.priority?.length) {
        matches = matches && filters.priority.includes(deal.priority);
      }
      if (filters.value?.min || filters.value?.max) {
        const dealValue = parseFloat(deal.value) || 0;
        if (filters.value.min) {
          matches = matches && dealValue >= parseFloat(filters.value.min);
        }
        if (filters.value.max) {
          matches = matches && dealValue <= parseFloat(filters.value.max);
        }
      }
      if (filters.agent_id) {
        matches = matches && deal.assignee?.id === filters.agent_id;
      }
      if (filters.date?.start || filters.date?.end) {
        const dealDate = new Date(deal.createdAt);
        if (filters.date.start) {
          matches = matches && dealDate >= new Date(filters.date.start);
        }
        if (filters.date.end) {
          matches = matches && dealDate <= new Date(filters.date.end);
        }
      }
      return matches;
    });
  }

  return filtered;
});

const handleSearch = query => {
  searchQuery.value = query;
};

const handleFilter = filters => {
  activeFilters.value = filters;
};

const searchResults = computed(() => {
  if (!searchQuery.value) return { total: 0, stages: {} };

  const results = {
    total: filteredDeals.value.length,
    stages: {},
  };

  filteredDeals.value.forEach(deal => {
    if (!results.stages[deal.stageName]) {
      results.stages[deal.stageName] = 0;
    }
    results.stages[deal.stageName]++;
  });

  return results;
});

const groupedDeals = computed(() => {
  const currentFunnel = selectedFunnel.value;
  if (!currentFunnel?.stages) {
    return [];
  }
  const groups = {};
  Object.entries(currentFunnel.stages).forEach(([stageId, stageInfo]) => {
    groups[stageId] = {
      id: stageId,
      name: stageInfo.name || '',
      color: stageInfo.color || '#64748B',
      deals: [],
      totalValue: 0,
      position: stageInfo.position || 0,
    };
  });
  filteredDeals.value.forEach(deal => {
    if (groups[deal.stage]) {
      groups[deal.stage].deals.push(deal);
      groups[deal.stage].totalValue += Number(deal.value) || 0;
    }
  });
  return Object.values(groups).sort((a, b) => a.position - b.position);
});

const getFriendlyStageLabel = stageKey => {
  if (stageKey.startsWith('etapa_')) {
    const num = stageKey.replace('etapa_', '');
    return `Etapa ${num}`;
  }
  return stageKey.charAt(0).toUpperCase() + stageKey.slice(1);
};

const fetchConversationData = async deal => {
  if (!deal.item_details?.conversation_id) return;
  try {
    const response = await conversationAPI.get({});
    const conversations = response.data.data.payload;
    conversationData.value[deal.id] = conversations.find(
      c => c.id === deal.item_details.conversation_id
    );
  } catch (error) {
    console.error('Erro ao carregar dados da conversa:', error);
  }
};

const handleEdit = deal => {
  itemToEdit.value = {
    id: deal.id,
    title: deal.title,
    description: deal.description,
    funnel_id: selectedFunnel.value?.id,
    funnel_stage: deal.stage,
    item_details: {
      title: deal.title,
      description: deal.description,
      priority: deal.priority,
      value: deal.value,
      agent_id: deal.assignee?.id,
    },
    custom_attributes: deal.custom_attributes || {},
  };
  showEditModal.value = true;
};

const handleItemEdited = () => {
  showEditModal.value = false;
  itemToEdit.value = null;
  emit('force-update');
};

const handleDelete = deal => {
  itemToDelete.value = deal;
  showDeleteModal.value = true;
};

const confirmDelete = async () => {
  if (!itemToDelete.value) return;
  try {
    isDeleting.value = true;
    await KanbanAPI.deleteItem(itemToDelete.value.id);
    emit('force-update');
    showDeleteModal.value = false;
    itemToDelete.value = null;
  } catch (error) {
    console.error('Erro ao excluir item:', error);
  } finally {
    isDeleting.value = false;
  }
};

const handleContextMenu = (e, deal) => {
  e.preventDefault();
  selectedDeal.value = deal;
  showContextMenu.value = true;
  contextMenuPosition.value = {
    x: e.clientX,
    y: e.clientY,
  };
};

const handleQuickMessage = () => {
  showContextMenu.value = false;
  showSendMessageModal.value = true;
};

const handleViewContact = () => {
  showContextMenu.value = false;
  const conversation = conversationData.value[selectedDeal.value.id];
  if (!conversation?.meta?.sender?.id) return;
  router.push({
    name: 'contact_profile',
    params: {
      accountId: conversation.account_id,
      contactId: conversation.meta.sender.id,
    },
    query: { page: 1 },
  });
};

const handleSendMessage = () => {
  showSendMessageModal.value = false;
  showContextMenu.value = false;
};

const handleItemClick = deal => {
  emit('itemClick', deal);
};

watch(groupedDeals, async newGroups => {
  const fetchPromises = newGroups.flatMap(group =>
    group.deals
      .filter(deal => deal.item_details?.conversation_id)
      .map(fetchConversationData)
  );
  await Promise.all(fetchPromises);
});

const navigateToConversation = (e, conversationId) => {
  e.stopPropagation();
  if (!conversationId || !conversationData.value[selectedDeal.value.id]) return;
  try {
    const conversation = conversationData.value[selectedDeal.value.id];
    router.push({
      name: 'inbox_conversation_through_inbox',
      params: {
        accountId: conversation.account_id,
        conversationId: conversationId,
      },
    });
  } catch (error) {
    console.error('Erro ao navegar para a conversa:', error);
    const conversation = conversationData.value[selectedDeal.value.id];
    window.location.href = `/app/accounts/${conversation.account_id}/conversations/${conversationId}`;
  }
};

const toggleStage = stageId => {
  if (expandedStages.value.has(stageId)) {
    expandedStages.value.delete(stageId);
  } else {
    expandedStages.value.add(stageId);
  }
};

const isStageExpanded = stageId => expandedStages.value.has(stageId);

const refreshData = () => {
  emit('force-update');
};
</script>

<template>
  <div class="flex flex-col h-full w-full bg-white dark:bg-slate-900">
    <KanbanHeader
      :current-view="currentView"
      :search-results="searchResults"
      :active-filters="activeFilters"
      @filter="handleFilter"
      @search="handleSearch"
      @switch-view="view => emit('switch-view', view)"
    />

    <div class="deals-list p-4 flex-1 overflow-auto w-full">
      <div
        v-if="isKanbanLoading || isLoading"
        class="flex justify-center items-center py-12"
      >
        <span class="loading-spinner" />
      </div>

      <div
        v-else-if="errorMessage"
        class="flex justify-center items-center py-12 text-ruby-500"
      >
        {{ errorMessage }}
      </div>

      <div
        v-else-if="!filteredDeals.length"
        class="flex flex-col items-center justify-center py-12"
      >
        <fluent-icon icon="task" size="48" class="mb-4 text-slate-400" />
        <p class="text-lg text-slate-600">{{ t('KANBAN.NO_ITEMS') }}</p>
      </div>

      <div v-else class="space-y-2 w-full max-w-full">
        <div
          v-for="stage in groupedDeals"
          :key="stage.id"
          class="deal-group w-full bg-white dark:bg-slate-900 rounded-lg border border-slate-200 dark:border-slate-700"
        >
          <div
            class="stage-header p-3 flex items-center justify-between bg-slate-50 dark:bg-slate-800 rounded-t-lg cursor-pointer"
            @click="toggleStage(stage.id)"
          >
            <div class="flex items-center gap-2">
              <span
                class="w-3 h-3 rounded-full"
                :style="{ backgroundColor: stage.color }"
              />
              <h3 class="font-medium text-slate-800 dark:text-slate-200">
                {{ stage.name }}
              </h3>
              <span
                class="px-2 py-0.5 text-xs font-medium rounded-full bg-slate-200 dark:bg-slate-700"
              >
                {{ stage.deals.length }}
              </span>
            </div>
            <div class="flex items-center gap-2">
              <div
                class="text-sm font-medium text-slate-700 dark:text-slate-300"
              >
                {{
                  new Intl.NumberFormat('pt-BR', {
                    style: 'currency',
                    currency: t('KANBAN.CURRENCY'),
                  }).format(stage.totalValue)
                }}
              </div>
              <fluent-icon
                :icon="
                  isStageExpanded(stage.id) ? 'chevron-up' : 'chevron-down'
                "
                size="16"
                class="text-slate-500"
              />
            </div>
          </div>

          <div
            v-show="isStageExpanded(stage.id)"
            class="divide-y divide-slate-100 dark:divide-slate-800"
          >
            <div
              v-for="deal in stage.deals"
              :key="deal.id"
              class="p-3 hover:bg-slate-50 dark:hover:bg-slate-800/50 cursor-pointer flex items-center gap-3"
              @click="handleItemClick(deal)"
            >
              <div class="flex-1">
                <div class="flex items-center gap-2">
                  <div class="font-medium text-slate-900 dark:text-slate-100">
                    {{ deal.title }}
                  </div>
                </div>
                <div
                  v-if="deal.description"
                  class="text-sm text-slate-500 dark:text-slate-400 truncate max-w-md"
                >
                  {{ deal.description }}
                </div>
              </div>

              <div
                class="text-right text-sm font-medium text-slate-800 dark:text-slate-200"
              >
                {{
                  new Intl.NumberFormat('pt-BR', {
                    style: 'currency',
                    currency: t('KANBAN.CURRENCY'),
                  }).format(deal.value)
                }}
              </div>

              <div v-if="deal.assignee" class="flex items-center gap-2">
                <span
                  v-if="!deal.assignee.avatar"
                  class="w-8 h-8 rounded-full bg-slate-200 flex items-center justify-center text-sm font-medium text-slate-600"
                >
                  {{ deal.assignee.name.charAt(0) }}
                </span>
                <img
                  v-else
                  :src="deal.assignee.avatar"
                  :alt="deal.assignee.name"
                  class="w-8 h-8 rounded-full"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

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
        {{ t('KANBAN.DELETE.TITLE') }}
      </h3>
      <p class="text-sm text-slate-600 mb-6">
        {{ t('KANBAN.DELETE.DESCRIPTION', { item: itemToDelete?.title }) }}
      </p>
      <div class="flex justify-end gap-2">
        <woot-button
          variant="clear"
          size="small"
          @click="showDeleteModal = false"
        >
          {{ t('KANBAN.CANCEL') }}
        </woot-button>
        <woot-button
          variant="danger"
          size="small"
          :loading="isDeleting"
          @click="confirmDelete"
        >
          {{ t('KANBAN.DELETE') }}
        </woot-button>
      </div>
    </div>
  </Modal>
</template>

<style lang="scss" scoped>
.deals-list {
  min-height: 0;
  width: 100%;
}

.loading-spinner {
  width: 24px;
  height: 24px;
  border: 2px solid #e2e8f0;
  border-top: 2px solid #4f46e5;
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

.deal-group {
  animation: fadeIn 0.2s ease-out forwards;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(5px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.deal-group:nth-child(1) {
  animation-delay: 0s;
}
.deal-group:nth-child(2) {
  animation-delay: 0.05s;
}
.deal-group:nth-child(3) {
  animation-delay: 0.1s;
}
.deal-group:nth-child(4) {
  animation-delay: 0.15s;
}
.deal-group:nth-child(5) {
  animation-delay: 0.2s;
}
</style>
