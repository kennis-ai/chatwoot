<script setup>
import { computed, ref, onMounted, onUnmounted, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useConfig } from 'dashboard/composables/useConfig';
import KanbanItem from './KanbanItem.vue';
import Modal from '../../../../components/Modal.vue';
import StageColorPicker from './StageColorPicker.vue';
import FunnelAPI from '../../../../api/funnel';
import KanbanAPI from '../../../../api/kanban';
import { emitter } from 'shared/helpers/mitt';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import KanbanStageReport from './KanbanStageReport.vue';
import AgentTooltip from './AgentTooltip.vue';
import PriorityCircle from './PriorityCircle.vue';

const props = defineProps({
  id: {
    type: String,
    required: true,
  },
  title: {
    type: String,
    required: true,
  },
  color: {
    type: String,
    default: 'orange',
  },
  // Remover a prop items - agora será buscado internamente
  totalColumns: {
    type: Number,
    default: 0,
  },
  description: {
    type: String,
    default: '',
  },
  isExpanded: {
    type: Boolean,
    default: false,
  },
  searchQuery: {
    type: String,
    default: '',
  },
  searchResults: {
    type: Object,
    default: null,
  },
  activeFilters: {
    type: Object,
    default: null,
  },
  globalStatusFilters: {
    type: Object,
    default: () => ({ won: true, lost: true }),
  },
});

const emit = defineEmits([
  'add',
  'edit',
  'delete',
  'drop',
  'itemClick',
  'itemsUpdated',
  'itemDragstart',
  'itemDragend',
  'expand',
  'closeExpanded',
]);
const { t, locale } = useI18n();

const store = useStore();
const { isStacklab } = useConfig();

// Buscar funil selecionado do Vuex (mantemos isso)
const selectedFunnel = computed(
  () => store.getters['funnel/getSelectedFunnel']
);
const stageStats = computed(() => {
  if (!selectedFunnel.value) return {};
  return store.getters['funnel/getStageStats'](selectedFunnel.value.id) || {};
});
const currentStageStats = computed(() => {
  const stats = stageStats.value[props.id] || {};
  return stats;
});

// Estado local para itens da coluna - busca direta da API
const columnItems = ref([]);
const isLoadingColumn = ref(false);
const currentPage = ref(1);
const hasMoreItems = ref(true);
const isLoadingMore = ref(false);

// Computed para verificar se há mais páginas baseado nos counts do header
const hasMorePages = computed(() => {
  const totalItemsInColumn = currentStageStats.value.count || 0;
  const currentItemsInColumn = columnItems.value.length;
  return currentItemsInColumn < totalItemsInColumn && hasMoreItems.value;
});

const showOptionsMenu = ref(false);
const columnSettings = ref({
  showWon: true,
  showLost: true,
  showAll: true,
  hideColumn: false,
  showTotal: true,
});

const showEditStageModal = ref(false);
const editingStageForm = ref({
  name: '',
  color: '',
  description: '',
});

// Adicionar ref para controle do modal de ordenação
const showSortModal = ref(false);
const columnSort = ref({
  type: 'created_at', // default: data de criação
  direction: 'desc', // default: mais recentes primeiro
});

// Garantir valores padrão para ordenação
const defaultSort = {
  type: 'created_at',
  direction: 'desc',
};

// Nova ref para controlar o estado de colapso em massa
const allItemsCollapsed = ref(false);

// Refs para Lazy Loading - removido, agora usa paginação simples
const scrollContainer = ref(null); // Ref para o container de scroll

// Refs para redimensionamento
const customWidth = ref(null);
const isResizing = ref(false);
const columnRef = ref(null);

// Ref para controlar estado de drag over
const isDraggingOver = ref(false);
const dragPlaceholderIndex = ref(-1);

// Opções de ordenação disponíveis
const sortOptions = [
  { id: 'created_at', label: 'Data de Criação' },
  { id: 'updated_at', label: 'Data de Modificação' },
  { id: 'title', label: 'Título' },
  { id: 'priority', label: 'Prioridade' },
  { id: 'value', label: 'Valor' },
];

// Context menu customizado para o header
const showHeaderContextMenu = ref(false);
const contextMenuPosition = ref({ x: 0, y: 0 });

const showTotalTooltip = ref(false);

// Computed para extrair até 3 agentes únicos dos cards da etapa
const agentAvatars = computed(() => {
  const agents = [];
  const seen = new Set();
  for (const item of filteredItems.value) {
    // Usar a mesma lógica do KanbanItem.vue para priorizar assigned_agents
    let itemAgents = [];

    // Usa assigned_agents se existir e tiver conteúdo
    if (item.assigned_agents && item.assigned_agents.length > 0) {
      itemAgents = item.assigned_agents;
    }

    // Adiciona cada agente único à lista
    for (const agent of itemAgents) {
      if (agent && agent.id && !seen.has(agent.id)) {
        agents.push({
          id: agent.id,
          name: agent.name,
          avatar_url: agent.avatar_url || agent.thumbnail || '',
        });
        seen.add(agent.id);
        if (agents.length === 2) break;
      }
    }

    if (agents.length === 2) break;
  }
  return agents;
});

const extraAgentsCount = computed(() => {
  const allAgentIds = new Set();
  for (const item of filteredItems.value) {
    // Usar a mesma lógica para coletar IDs de agentes
    let itemAgents = [];

    // Usa assigned_agents se existir e tiver conteúdo
    if (item.assigned_agents && item.assigned_agents.length > 0) {
      itemAgents = item.assigned_agents;
    }

    // Adiciona todos os IDs de agente únicos
    for (const agent of itemAgents) {
      if (agent && agent.id) {
        allAgentIds.add(agent.id);
      }
    }
  }
  return Math.max(0, allAgentIds.size - 2); // Mudei de -3 para -2 pois agentAvatars mostra apenas 2
});

// Título truncado para exibição
const truncatedTitle = computed(() => {
  // Remover truncamento, mostrar título completo
  return props.title || '';
});

// Função para buscar itens da API
const fetchColumnItems = async (page = 1, reset = false) => {
  if (isLoadingColumn.value) return;

  try {
    isLoadingColumn.value = true;
    if (page > 1) {
      isLoadingMore.value = true;
    }

    const response = await KanbanAPI.getItems(
      selectedFunnel.value?.id,
      page,
      props.id // stageId
    );

    const items = response.data.items || response.data;
    const pagination = response.data.pagination;

    if (reset || page === 1) {
      columnItems.value = items;
      currentPage.value = 1;
    } else {
      columnItems.value = [...columnItems.value, ...items];
    }

    currentPage.value = page;
    hasMoreItems.value = pagination ? pagination.has_more : items.length === 50;
  } catch (error) {
    console.error(
      `[KANBAN-COLUMN] Erro ao buscar itens da coluna ${props.id}:`,
      error
    );
  } finally {
    isLoadingColumn.value = false;
    isLoadingMore.value = false;
  }
};

// Funções de redimensionamento
const startResize = e => {
  if (props.isExpanded) return;
  columnRef.value = e.target.closest('.kanban-column-root');
  isResizing.value = true;
  document.body.style.cursor = 'col-resize';
  document.body.style.userSelect = 'none';
  e.preventDefault();
};

const handleResize = e => {
  if (!isResizing.value || !columnRef.value) return;
  const rect = columnRef.value.getBoundingClientRect();
  const newWidth = e.clientX - rect.left;
  if (newWidth >= 300 && newWidth <= 800) {
    customWidth.value = newWidth;
  }
};

const stopResize = () => {
  if (isResizing.value) {
    isResizing.value = false;
    columnRef.value = null;
    document.body.style.cursor = '';
    document.body.style.userSelect = '';
    if (customWidth.value) {
      localStorage.setItem(
        `kanban_column_${props.id}_width`,
        customWidth.value
      );
    }
  }
};

const resetWidth = () => {
  customWidth.value = null;
  localStorage.removeItem(`kanban_column_${props.id}_width`);
};

// Carregar configurações do localStorage
onMounted(async () => {
  // Load non-filter settings
  const savedSettings = localStorage.getItem(
    `kanban_column_${props.id}_settings`
  );
  if (savedSettings) {
    columnSettings.value = JSON.parse(savedSettings);
  }
  const savedSort = localStorage.getItem(`kanban_column_${props.id}_sort`);
  if (savedSort) {
    try {
      const parsedSort = JSON.parse(savedSort);
      columnSort.value = { ...defaultSort, ...parsedSort };
    } catch (e) {
      console.error(`Error parsing saved sort for column ${props.id}:`, e);
      columnSort.value = { ...defaultSort };
    }
  } else {
    // Garantir valores padrão mesmo quando não há configuração salva
    columnSort.value = { ...defaultSort };
  }

  // Carregar largura customizada
  const savedWidth = localStorage.getItem(`kanban_column_${props.id}_width`);
  if (savedWidth) {
    customWidth.value = parseInt(savedWidth, 10);
  }

  // Fechar menu ao clicar fora
  document.addEventListener('click', closeOptionsMenuOnClickOutside);
  document.addEventListener('click', closeHeaderContextMenu);

  // Event listeners para redimensionamento
  document.addEventListener('mousemove', handleResize);
  document.addEventListener('mouseup', stopResize);

  // Ouvir eventos de atualização de itens
  emitter.on('kanbanItemUpdated', handleItemUpdated);
  emitter.on('kanbanItemCreated', handleItemUpdated);

  // ✅ NOVO: Ouvir evento direto de movimento
  emitter.on('kanbanItemMoved', handleItemMoved);

  // ✅ NOVO: Ouvir evento de delete
  emitter.on('kanbanItemDeleted', ({ itemId }) => {
    const initialCount = columnItems.value.length;
    columnItems.value = columnItems.value.filter(
      item => Number(item.id) !== Number(itemId)
    );
    const finalCount = columnItems.value.length;
  });

  // ✅ NOVO: Ouvir evento de movimento entre etapas
  emitter.on(
    'kanbanItemMovedBetweenStages',
    ({ itemId, fromStage, toStage, funnelId }) => {
      // Só reagir se esta coluna estiver envolvida no movimento
      if (props.id === fromStage || props.id === toStage) {
        // Buscar novamente os stats da API para esta coluna
        fetchStageStatsFromAPI(itemId);
      }
    }
  );

  // Buscar stats ao montar ou ao trocar de funil
  if (selectedFunnel.value) {
    store.dispatch('funnel/fetchStageStats', {
      funnelId: selectedFunnel.value.id,
      filterParams: {},
    });
    // Buscar itens da coluna
    await fetchColumnItems(1, true);
  }
});

// Watch para mudanças no funil selecionado
watch(selectedFunnel, async (newFunnel, oldFunnel) => {
  if (newFunnel && newFunnel.id !== oldFunnel?.id) {
    await fetchColumnItems(1, true);
  }
});

// Watch para mudanças nos filtros - atualizar stats
watch(
  () => [props.activeFilters, props.globalStatusFilters],
  async () => {
    if (selectedFunnel.value) {
      await fetchStageStatsFromAPI();
    }
  },
  { deep: true }
);

// ✅ NOVO: Listener robusto para eventos diretos de movimento
const handleItemMoved = ({ itemId, fromStage, toStage, itemData }) => {
  const numericItemId = Number(itemId);

  // ✅ REMOVER DA COLUNA DE ORIGEM (se conhecida)
  if (fromStage && props.id === fromStage) {
    const initialCount = columnItems.value.length;
    columnItems.value = columnItems.value.filter(
      item => Number(item.id) !== numericItemId
    );
    const finalCount = columnItems.value.length;
  }

  // ✅ ADICIONAR À COLUNA DE DESTINO
  if (props.id === toStage) {
    if (!itemData) {
      console.error(`[KANBAN-COLUMN] Dados do item não fornecidos para adição`);
      return;
    }

    const existingIndex = columnItems.value.findIndex(
      item => Number(item.id) === numericItemId
    );
    const initialCount = columnItems.value.length;

    if (existingIndex >= 0) {
      // Atualizar item existente
      columnItems.value[existingIndex] = { ...itemData };
    } else {
      // Adicionar item novo
      columnItems.value.push({ ...itemData });
    }

    // Forçar reatividade
    columnItems.value = [...columnItems.value];

    const finalCount = columnItems.value.length;
  }

  // ✅ FALLBACK: Se fromStage é undefined, tentar remover de qualquer coluna que tenha o item
  if (!fromStage && props.id !== toStage) {
    const hasItem = columnItems.value.some(
      item => Number(item.id) === numericItemId
    );
    if (hasItem) {
      columnItems.value = columnItems.value.filter(
        item => Number(item.id) !== numericItemId
      );
    }
  }
};

// Salvar configurações no localStorage
const saveColumnSettings = () => {
  localStorage.setItem(
    `kanban_column_${props.id}_settings`,
    JSON.stringify(columnSettings.value)
  );
};

// Salvar configurações de ordenação
const saveSortSettings = () => {
  localStorage.setItem(
    `kanban_column_${props.id}_sort`,
    JSON.stringify(columnSort.value)
  );
};

const filteredItems = computed(() => {
  console.log(
    '[KanbanColumn] filteredItems computed - activeFilters recebidos:',
    props.activeFilters
  );
  console.log(
    '[KanbanColumn] filteredItems computed - columnItems length:',
    columnItems.value.length
  );
  console.log(
    '[KanbanColumn] filteredItems computed - searchResults:',
    props.searchResults
  );

  if (columnSettings.value.hideColumn) {
    return [];
  }

  // 1. If we have search results, use only items from search that belong to this stage
  if (props.searchResults && props.searchResults.items) {
    const searchItems = props.searchResults.items.filter(
      item => item.funnel_stage === props.id
    );

    // Apply additional filters to search results
    let items = [...searchItems];

    // Apply active filters to search results
    if (props.activeFilters) {
      console.log(
        '[KanbanColumn] Aplicando filtros aos resultados da busca...'
      );
      items = items.filter(item => {
        // Filter by priority
        if (
          props.activeFilters.priorities &&
          props.activeFilters.priorities.length > 0
        ) {
          const itemPriority = item.item_details?.priority || 'none';
          if (!props.activeFilters.priorities.includes(itemPriority))
            return false;
        }

        // Filter by agent
        const agentFilter =
          props.activeFilters.agent_id || props.activeFilters.agent;
        if (agentFilter && agentFilter !== '') {
          let itemAgentId = null;

          if (
            item.assigned_agents &&
            Array.isArray(item.assigned_agents) &&
            item.assigned_agents.length > 0
          ) {
            itemAgentId = item.assigned_agents[0].id;
          } else {
            itemAgentId =
              item.assigned_agent_id ||
              item.assignee_id ||
              (item.item_details && item.item_details.agent_id) ||
              (item.meta && item.meta.agent_id) ||
              null;
          }

          if (agentFilter === -1 || agentFilter === '-1') {
            if (itemAgentId !== null) {
              return false;
            }
            return true;
          }

          if (itemAgentId == null || itemAgentId != agentFilter) {
            return false;
          }
        }

        return true;
      });
    }

    // Apply global status filters
    if (props.globalStatusFilters) {
      items = items.filter(item => {
        if (!item || !item.item_details) return true;

        const itemStatus = item.item_details?.status?.toLowerCase();

        if (!props.globalStatusFilters.won && itemStatus === 'won') {
          return false;
        }

        if (!props.globalStatusFilters.lost && itemStatus === 'lost') {
          return false;
        }

        return true;
      });
    }

    // Apply sorting
    return items.sort((a, b) => {
      const direction = columnSort.value.direction === 'asc' ? 1 : -1;
      const type = columnSort.value.type || 'created_at';

      let valueA;
      let valueB;

      switch (type) {
        case 'title':
          valueA = a.item_details?.title || '';
          valueB = b.item_details?.title || '';
          return direction * valueA.localeCompare(valueB);

        case 'priority': {
          const priorityOrder = {
            urgent: 4,
            high: 3,
            medium: 2,
            low: 1,
            none: 0,
          };
          valueA = priorityOrder[a.item_details?.priority || 'none'];
          valueB = priorityOrder[b.item_details?.priority || 'none'];
          return direction * (valueA - valueB);
        }

        case 'value':
          valueA = parseFloat(a.item_details?.value) || 0;
          valueB = parseFloat(b.item_details?.value) || 0;
          return direction * (valueA - valueB);

        case 'updated_at':
          valueA = new Date(a.updated_at);
          valueB = new Date(b.updated_at);

          if (isNaN(valueA.getTime())) return direction;
          if (isNaN(valueB.getTime())) return -direction;

          return direction * (valueA - valueB);

        case 'created_at':
        default:
          valueA = new Date(a.created_at);
          valueB = new Date(b.created_at);

          if (isNaN(valueA.getTime())) return direction;
          if (isNaN(valueB.getTime())) return -direction;

          const result = direction * (valueA - valueB);
          return result;
      }
    });
  }

  // 2. Start with the items for this column (original logic)
  let items = [...columnItems.value];

  // 2. Apply search filter if there's a search query
  if (props.searchQuery && props.searchQuery.trim()) {
    const query = props.searchQuery.toLowerCase().trim();

    items = items.filter(item => {
      if (!item || !item.item_details) return false;

      const title = (item.item_details.title || '').toLowerCase();
      const description = (item.item_details.description || '').toLowerCase();
      const customerName = (
        item.item_details.customer_name || ''
      ).toLowerCase();
      const customerEmail = (
        item.item_details.customer_email || ''
      ).toLowerCase();

      const matches =
        title.includes(query) ||
        description.includes(query) ||
        customerName.includes(query) ||
        customerEmail.includes(query);

      return matches;
    });
  }

  // 2. Apply active filters from KanbanTab
  console.log(
    '[KanbanColumn] Aplicando filtros ativos - items antes do filtro:',
    items.length
  );
  if (props.activeFilters) {
    console.log('[KanbanColumn] Filtros ativos encontrados, aplicando...');
    items = items.filter(item => {
      // Filter by priority
      if (
        props.activeFilters.priorities &&
        props.activeFilters.priorities.length > 0
      ) {
        const itemPriority = item.item_details?.priority || 'none'; // Default to 'none' if undefined
        if (!props.activeFilters.priorities.includes(itemPriority))
          return false;
      }

      // Filter by value
      if (
        (props.activeFilters.valueMin !== undefined &&
          props.activeFilters.valueMin !== null) ||
        (props.activeFilters.valueMax !== undefined &&
          props.activeFilters.valueMax !== null)
      ) {
        const itemValue = parseFloat(item.item_details?.value) || 0;
        const min = props.activeFilters.valueMin;
        const max = props.activeFilters.valueMax;

        if (min !== undefined && min !== null && itemValue < min) return false;
        if (max !== undefined && max !== null && itemValue > max) return false;
      }

      // Filter by agent (from KanbanHeader or KanbanFilter)
      const agentFilter =
        props.activeFilters.agent_id || props.activeFilters.agent;
      if (agentFilter && agentFilter !== '') {
        // Verificar várias possíveis propriedades onde o ID do agente pode estar armazenado
        let itemAgentId = null;

        // Primeiro, verificar se tem assigned_agents como array
        if (
          item.assigned_agents &&
          Array.isArray(item.assigned_agents) &&
          item.assigned_agents.length > 0
        ) {
          itemAgentId = item.assigned_agents[0].id; // Pegar o primeiro agente do array
        } else {
          // Fallback para outras propriedades
          itemAgentId =
            item.assigned_agent_id ||
            item.assignee_id ||
            (item.item_details && item.item_details.agent_id) ||
            (item.meta && item.meta.agent_id) ||
            null;
        }

        // Caso especial: -1 significa "Não atribuído" (filtra por itens sem agente)
        if (agentFilter === -1 || agentFilter === '-1') {
          // Se o item TEM um agente atribuído, rejeitar
          if (itemAgentId !== null) {
            return false;
          }
          return true;
        }

        // Caso normal: filtrar por ID do agente
        if (itemAgentId == null || itemAgentId != agentFilter) {
          return false;
        }
      }

      // Filter by channel (from KanbanHeader)
      if (props.activeFilters.channel && props.activeFilters.channel !== '') {
        // Verificar o canal do item (usando a mesma lógica do inbox)
        let itemChannel = '';

        // Primeiro, tentar pegar do conversation.inbox.channel_type
        if (
          item.conversation &&
          item.conversation.inbox &&
          item.conversation.inbox.channel_type
        ) {
          itemChannel = item.conversation.inbox.channel_type;
        } else {
          // Fallback para outras propriedades
          itemChannel =
            item.channel_type ||
            (item.item_details && item.item_details.channel_type) ||
            (item.conversation && item.conversation.channel_type) ||
            (item.inbox && item.inbox.channel_type) ||
            '';
        }

        const channelType = itemChannel.replace('Channel::', '');

        console.log('[KanbanColumn] Filter by channel:', {
          itemId: item.id,
          itemChannel,
          channelType,
          filterChannel: props.activeFilters.channel,
          match: channelType === props.activeFilters.channel,
        });

        if (channelType !== props.activeFilters.channel) {
          return false;
        }
      }

      // Filter by date
      if (
        (props.activeFilters.dateStart &&
          props.activeFilters.dateStart !== '') ||
        (props.activeFilters.dateEnd && props.activeFilters.dateEnd !== '')
      ) {
        const itemDate = new Date(item.created_at);
        if (isNaN(itemDate.getTime())) return false; // Skip invalid dates

        if (
          props.activeFilters.dateStart &&
          props.activeFilters.dateStart !== ''
        ) {
          const startDate = new Date(props.activeFilters.dateStart);
          startDate.setHours(0, 0, 0, 0); // Compare from the beginning of the day
          if (itemDate < startDate) return false;
        }
        if (props.activeFilters.dateEnd && props.activeFilters.dateEnd !== '') {
          const endDate = new Date(props.activeFilters.dateEnd);
          endDate.setHours(23, 59, 59, 999); // Compare until the end of the day
          if (itemDate > endDate) return false;
        }
      }

      return true; // Item passes all local filters
    });
  }

  // 3. Apply global status filters (won/lost)
  if (props.globalStatusFilters) {
    items = items.filter(item => {
      if (!item || !item.item_details) return true; // Se não tem dados, manter

      const itemStatus = item.item_details?.status?.toLowerCase();

      // Se filtro 'won' está desabilitado e item é 'won', remover
      if (!props.globalStatusFilters.won && itemStatus === 'won') {
        return false;
      }

      // Se filtro 'lost' está desabilitado e item é 'lost', remover
      if (!props.globalStatusFilters.lost && itemStatus === 'lost') {
        return false;
      }

      return true;
    });
  }

  // 4. Apply sorting - Garantir ordenação por data de criação decrescente por padrão

  return items.sort((a, b) => {
    const direction = columnSort.value.direction === 'asc' ? 1 : -1;
    const type = columnSort.value.type || 'created_at'; // Garantir valor padrão

    let valueA;
    let valueB;

    switch (type) {
      case 'title':
        valueA = a.item_details?.title || '';
        valueB = b.item_details?.title || '';
        return direction * valueA.localeCompare(valueB);

      case 'priority': {
        const priorityOrder = {
          urgent: 4,
          high: 3,
          medium: 2,
          low: 1,
          none: 0, // Ensure 'none' or undefined priority is handled
        };
        valueA = priorityOrder[a.item_details?.priority || 'none'];
        valueB = priorityOrder[b.item_details?.priority || 'none'];
        return direction * (valueA - valueB);
      }

      case 'value':
        valueA = parseFloat(a.item_details?.value) || 0;
        valueB = parseFloat(b.item_details?.value) || 0;
        return direction * (valueA - valueB);

      case 'updated_at':
        valueA = new Date(a.updated_at);
        valueB = new Date(b.updated_at);

        if (isNaN(valueA.getTime())) return direction;
        if (isNaN(valueB.getTime())) return -direction;

        return direction * (valueA - valueB);

      case 'created_at': // Default sorting - mais recentes primeiro
      default:
        valueA = new Date(a.created_at);
        valueB = new Date(b.created_at);

        // Handle potential invalid dates during sorting
        if (isNaN(valueA.getTime())) return direction;
        if (isNaN(valueB.getTime())) return -direction;

        // Para ordenação decrescente (mais recentes primeiro), comparamos B - A
        // direction = -1 para desc, 1 para asc
        const result = direction * (valueA - valueB);
        return result;
    }
  });

  console.log(
    '[KanbanColumn] filteredItems computed - items após todos os filtros:',
    items.length
  );
  return items;
});

// Lista de itens a serem realmente exibidos - mostrar todos os itens da coluna
const displayedItems = computed(() => {
  return filteredItems.value;
});

// Computed para obter moeda padrão baseada no i18n (reativo)
const defaultCurrency = computed(() => {
  const i18nLocale = locale.value || 'pt-BR';
  const currencyMap = {
    'pt-BR': { code: 'BRL', locale: 'pt-BR', symbol: 'R$' },
    pt_BR: { code: 'BRL', locale: 'pt-BR', symbol: 'R$' },
    'en-US': { code: 'USD', locale: 'en-US', symbol: '$' },
    en_US: { code: 'USD', locale: 'en-US', symbol: '$' },
    en: { code: 'USD', locale: 'en-US', symbol: '$' },
    'de-DE': { code: 'EUR', locale: 'de-DE', symbol: '€' },
    de_DE: { code: 'EUR', locale: 'de-DE', symbol: '€' },
    de: { code: 'EUR', locale: 'de-DE', symbol: '€' },
    'es-ES': { code: 'EUR', locale: 'es-ES', symbol: '€' },
    es_ES: { code: 'EUR', locale: 'es-ES', symbol: '€' },
    es: { code: 'EUR', locale: 'es-ES', symbol: '€' },
    'fr-FR': { code: 'EUR', locale: 'fr-FR', symbol: '€' },
    fr_FR: { code: 'EUR', locale: 'fr-FR', symbol: '€' },
    fr: { code: 'EUR', locale: 'fr-FR', symbol: '€' },
    'pt-PT': { code: 'EUR', locale: 'pt-PT', symbol: '€' },
    pt_PT: { code: 'EUR', locale: 'pt-PT', symbol: '€' },
  };

  return currencyMap[i18nLocale] || currencyMap['pt-BR'];
});

// Agrupar totais por moeda
const totalsByCurrency = computed(() => {
  const totals = {};
  const defCurrency = defaultCurrency.value;

  console.log('[KanbanColumn] Processando itens para totalsByCurrency:', {
    itemCount: filteredItems.value.length,
    defaultCurrency: defCurrency,
  });

  filteredItems.value.forEach((item, idx) => {
    const value = parseFloat(item.item_details?.value) || 0;

    // Obter informação de moeda do item ou usar padrão do i18n
    let currencyCode = defCurrency.code;
    let currencyLocale = defCurrency.locale;
    let currencySymbol = defCurrency.symbol;

    if (item.item_details?.currency) {
      currencyCode = item.item_details.currency.code || defCurrency.code;
      currencyLocale = item.item_details.currency.locale || defCurrency.locale;
      currencySymbol = item.item_details.currency.symbol || defCurrency.symbol;

      console.log(`[KanbanColumn] Item ${idx} (${item.id}):`, {
        value,
        hasCurrency: !!item.item_details.currency,
        currencyCode,
        currencyLocale,
        currencySymbol,
        itemCurrency: item.item_details.currency,
      });
    }

    // Inicializar moeda se não existir
    if (!totals[currencyCode]) {
      totals[currencyCode] = {
        code: currencyCode,
        locale: currencyLocale,
        symbol: currencySymbol,
        total: 0,
        count: 0,
      };
    }

    // Somar valor
    totals[currencyCode].total += value;
    totals[currencyCode].count += 1;
  });

  console.log('[KanbanColumn] Totals by currency final:', totals);
  return totals;
});

// Detectar moeda predominante (prioriza moeda do locale, depois a que tem mais itens)
const primaryCurrency = computed(() => {
  const currencies = Object.values(totalsByCurrency.value);
  const defCurrency = defaultCurrency.value;

  console.log('[KanbanColumn] primaryCurrency - currencies:', currencies);
  console.log(
    '[KanbanColumn] primaryCurrency - defaultCurrency (i18n):',
    defCurrency
  );

  if (currencies.length === 0) {
    // Fallback: usar locale do i18n
    console.log(
      '[KanbanColumn] primaryCurrency - usando fallback:',
      defCurrency
    );
    return defCurrency;
  }

  // Prioridade 1: Se existe a moeda do locale atual (i18n), usar ela
  const localeCurrency = currencies.find(
    curr => curr.code === defCurrency.code
  );
  if (localeCurrency) {
    console.log(
      '[KanbanColumn] primaryCurrency - usando moeda do locale:',
      localeCurrency
    );
    return localeCurrency;
  }

  // Prioridade 2: Retornar a moeda com mais itens
  const primary = currencies.reduce((prev, current) =>
    current.count > prev.count ? current : prev
  );

  console.log(
    '[KanbanColumn] primaryCurrency - usando moeda predominante:',
    primary
  );
  return primary;
});

// Total da moeda predominante
const columnTotal = computed(() => {
  return primaryCurrency.value.total || 0;
});

const formattedTotal = computed(() => {
  if (!columnTotal.value) return '';
  const currency = primaryCurrency.value;

  console.log('[KanbanColumn] formattedTotal:', {
    columnTotal: columnTotal.value,
    currency,
    primaryCurrency: primaryCurrency.value,
  });

  try {
    const formatted = new Intl.NumberFormat(currency.locale, {
      style: 'currency',
      currency: currency.code,
    }).format(columnTotal.value);
    console.log('[KanbanColumn] formattedTotal result:', formatted);
    return formatted;
  } catch (error) {
    console.error('[KanbanColumn] formattedTotal error:', error);
    // Fallback se houver erro de formatação
    return `${currency.symbol} ${columnTotal.value.toFixed(2)}`;
  }
});

const formattedTotalAbbreviated = computed(() => {
  const value = columnTotal.value;
  if (!value) return '';
  const abs = Math.abs(value);
  const currency = primaryCurrency.value;

  if (abs >= 1_000_000_000) {
    const short = (value / 1_000_000_000).toFixed(1).replace(/\.0$/, '') + 'B';
    return currency.symbol + ' ' + short;
  }
  if (abs >= 1_000_000) {
    const short = (value / 1_000_000).toFixed(1).replace(/\.0$/, '') + 'M';
    return currency.symbol + ' ' + short;
  }
  if (abs >= 1_000) {
    const short = (value / 1_000).toFixed(1).replace(/\.0$/, '') + 'K';
    return currency.symbol + ' ' + short;
  }
  return formattedTotal.value;
});

// Tooltip com todas as moedas
const allCurrenciesTooltip = computed(() => {
  const currencies = Object.values(totalsByCurrency.value);

  console.log('[KanbanColumn] allCurrenciesTooltip - currencies:', currencies);

  if (currencies.length === 0) return '';
  if (currencies.length === 1) return formattedTotal.value;

  // Montar tooltip com todas as moedas
  const tooltip = currencies
    .sort((a, b) => b.count - a.count) // Ordenar por quantidade de itens
    .map(curr => {
      try {
        const formatted = new Intl.NumberFormat(curr.locale, {
          style: 'currency',
          currency: curr.code,
        }).format(curr.total);
        return `${formatted} (${curr.count} ${curr.count === 1 ? 'item' : 'itens'})`;
      } catch (error) {
        return `${curr.symbol} ${curr.total.toFixed(2)} (${curr.count} ${curr.count === 1 ? 'item' : 'itens'})`;
      }
    })
    .join('\n');

  console.log('[KanbanColumn] allCurrenciesTooltip result:', tooltip);
  return tooltip;
});

const columnCount = computed(() => {
  // Se há filtros aplicados, usar filteredItems para count correto
  if (
    props.activeFilters ||
    (props.globalStatusFilters &&
      (!props.globalStatusFilters.won || !props.globalStatusFilters.lost))
  ) {
    return filteredItems.value.length;
  }
  // Se stats agregados disponíveis e sem filtros, usar
  if (typeof currentStageStats.value.count === 'number') {
    return currentStageStats.value.count;
  }
  // Fallback: calcular localmente
  return filteredItems.value.length;
});

const darkenColor = color => {
  const hex = color.replace('#', '');
  const r = parseInt(hex.substring(0, 2), 16);
  const g = parseInt(hex.substring(2, 4), 16);
  const b = parseInt(hex.substring(4, 6), 16);

  const darkenAmount = 0.65;
  const dr = Math.floor(r * darkenAmount);
  const dg = Math.floor(g * darkenAmount);
  const db = Math.floor(b * darkenAmount);

  return `#${dr.toString(16).padStart(2, '0')}${dg
    .toString(16)
    .padStart(2, '0')}${db.toString(16).padStart(2, '0')}`;
};

const textColor = computed(() =>
  props.color ? darkenColor(props.color) : '#CC6E00'
);

const columnStyle = computed(() => {
  if (props.isExpanded) {
    return {
      width: '100%',
      minWidth: '0',
      maxWidth: '100%',
      margin: '0',
      borderRadius: '1rem',
      boxShadow: 'none',
      boxSizing: 'border-box',
    };
  }
  return {
    backgroundColor: props.color ? `${props.color}40` : '#f8fafc',
  };
});

const countStyle = computed(() => ({
  backgroundColor: props.color ? `${props.color}15` : '#FFF4E5',
  color: textColor.value,
}));

// Função para buscar stats da etapa diretamente da API
const fetchStageStatsFromAPI = async itemId => {
  if (!selectedFunnel.value) return;

  try {
    // Primeiro, buscar os dados atuais do item para identificar movimento
    let originalStage = null;

    // Procurar o item nas colunas para identificar a etapa de origem
    if (itemId) {
      // Buscar o item na API para obter sua etapa original
      try {
        const itemResponse = await KanbanAPI.getItem(
          selectedFunnel.value.id,
          itemId
        );
        if (itemResponse.data && itemResponse.data.funnel_stage) {
          originalStage = itemResponse.data.funnel_stage;
        }
      } catch (itemError) {
        console.warn(
          `[KANBAN-COLUMN] Não foi possível obter etapa original do item ${itemId}:`,
          itemError
        );
      }
    }

    // Preparar parâmetros de filtro
    const filterParams = {};

    if (props.activeFilters) {
      if (props.activeFilters.priorities?.length > 0) {
        filterParams.priorities = props.activeFilters.priorities;
      }

      const agentFilter =
        props.activeFilters.agent_id || props.activeFilters.agent;
      if (agentFilter && agentFilter !== '') {
        filterParams.agent_id = agentFilter;
      }

      if (
        props.activeFilters.valueMin !== undefined &&
        props.activeFilters.valueMin !== null
      ) {
        filterParams.value_min = props.activeFilters.valueMin;
      }
      if (
        props.activeFilters.valueMax !== undefined &&
        props.activeFilters.valueMax !== null
      ) {
        filterParams.value_max = props.activeFilters.valueMax;
      }

      if (props.activeFilters.dateStart) {
        filterParams.date_start = props.activeFilters.dateStart;
      }
      if (props.activeFilters.dateEnd) {
        filterParams.date_end = props.activeFilters.dateEnd;
      }
    }

    // Aplicar filtros globais de status
    if (props.globalStatusFilters) {
      filterParams.show_won = props.globalStatusFilters.won;
      filterParams.show_lost = props.globalStatusFilters.lost;
    }

    // Fazer chamada direta para a API de stats do funil (retorna stats de todas as etapas)
    const response = await FunnelAPI.getStageStats(
      selectedFunnel.value.id,
      filterParams
    );

    if (response.data) {
      // Commit direto no store para atualizar os stats
      store.commit('funnel/SET_STAGE_STATS', {
        funnelId: selectedFunnel.value.id,
        stats: response.data.stages || response.data,
      });
    }
  } catch (error) {
    console.error(
      `[KANBAN-COLUMN] Erro ao buscar stats do funil da API:`,
      error
    );
  }
};

const handleDrop = event => {
  isDraggingOver.value = false;
  dragPlaceholderIndex.value = -1;

  const itemID = event.dataTransfer.getData('text/plain');

  if (itemID) {
    const numericId = parseInt(itemID, 10);

    // Garantir que o ID seja passado como número para o componente pai
    emit('drop', {
      itemId: numericId,
      columnId: props.id,
      funnelId: selectedFunnel.value.id,
    });

    // REMOVIDO: fetchStageStatsFromAPI será chamado pelo evento kanbanItemMovedBetweenStages
    // para evitar múltiplas chamadas
  }
};

const handleDragOver = event => {
  event.preventDefault();
  isDraggingOver.value = true;

  // Calcular a posição do placeholder baseado na posição Y do mouse
  const container = scrollContainer.value;
  if (!container || props.isExpanded) return;

  const mouseY = event.clientY;

  // Encontrar a posição correta para inserir o placeholder
  const items = container.querySelectorAll('.kanban-item-wrapper');
  let insertIndex = displayedItems.value.length;

  for (let i = 0; i < items.length; i++) {
    const itemRect = items[i].getBoundingClientRect();
    const itemMiddle = itemRect.top + itemRect.height / 2;

    if (mouseY < itemMiddle) {
      insertIndex = i;
      break;
    }
  }

  dragPlaceholderIndex.value = insertIndex;
};

const handleDragLeave = event => {
  // Verificar se realmente saiu da coluna (não apenas de um filho)
  if (event.currentTarget.contains(event.relatedTarget)) return;
  isDraggingOver.value = false;
  dragPlaceholderIndex.value = -1;
};

const columnWidth = computed(() => {
  if (props.isExpanded) {
    return {
      width: '100%',
      minWidth: '0',
      maxWidth: '100%',
      margin: '0',
      borderRadius: '0',
      boxShadow: 'none',
      boxSizing: 'border-box',
    };
  }
  if (customWidth.value) {
    return {
      width: `${customWidth.value}px`,
      minWidth: `${customWidth.value}px`,
      maxWidth: `${customWidth.value}px`,
      flexShrink: 0,
    };
  }
  if (props.totalColumns <= 5) {
    return {
      minWidth: '360px',
      maxWidth: `calc((100% - ${(props.totalColumns - 1) * 1}rem) / ${
        props.totalColumns
      })`,
      width: '100%',
    };
  }
  return {
    minWidth: '390px',
    maxWidth: '390px',
    width: '390px',
  };
});

// Função removida - agora usa paginação simples

// Remover o handleScroll antigo - agora usa botão
// const handleScroll = async () => { ... } - REMOVIDO

// Função para carregar mais itens
const loadMoreItems = async () => {
  if (hasMorePages.value && !isLoadingMore.value) {
    try {
      await fetchColumnItems(currentPage.value + 1, false);
    } catch (error) {
      console.error(
        `[KANBAN-COLUMN] Erro ao carregar mais itens para coluna ${props.id}:`,
        error
      );
    }
  }
};

// Fechar menu ao clicar fora
const closeOptionsMenuOnClickOutside = event => {
  // Lógica para verificar se o clique foi fora do botão e do menu
  // Esta função agora é nomeada para poder ser removida em onUnmounted
  // (Implementação simplificada, pode precisar de ajustes dependendo da estrutura exata do DOM)
  if (showOptionsMenu.value) {
    showOptionsMenu.value = false;
  }
};

// Context menu customizado para o header
const handleHeaderContextMenu = event => {
  event.preventDefault();
  showHeaderContextMenu.value = true;
  contextMenuPosition.value = { x: event.clientX, y: event.clientY };
};

const closeHeaderContextMenu = () => {
  showHeaderContextMenu.value = false;
};

const toggleShowTotal = () => {
  columnSettings.value.showTotal = !columnSettings.value.showTotal;
  saveColumnSettings();
  closeHeaderContextMenu();
};

onMounted(() => {
  document.addEventListener('click', closeOptionsMenuOnClickOutside);
  document.addEventListener('click', closeHeaderContextMenu);
});

// Handler para eventos de atualização de itens
const handleItemUpdated = updatedItem => {
  if (!updatedItem || updatedItem.funnel_stage !== props.id) return;

  // Verificar se o item já existe na coluna
  const existingIndex = columnItems.value.findIndex(
    item => item.id === updatedItem.id
  );

  if (existingIndex >= 0) {
    // Atualizar item existente
    columnItems.value[existingIndex] = { ...updatedItem };
    // Forçar reatividade
    columnItems.value = [...columnItems.value];
  } else {
    // Adicionar item novo à coluna se ele pertencer a esta coluna
    columnItems.value.push(updatedItem);
    columnItems.value = [...columnItems.value];
  }
};

onUnmounted(() => {
  document.removeEventListener('click', closeOptionsMenuOnClickOutside);
  document.removeEventListener('click', closeHeaderContextMenu);
  document.removeEventListener('mousemove', handleResize);
  document.removeEventListener('mouseup', stopResize);

  // Remover listeners de eventos
  emitter.off('kanbanItemUpdated', handleItemUpdated);
  emitter.off('kanbanItemCreated', handleItemUpdated);

  // ✅ NOVO: Remover listener de movimento
  emitter.off('kanbanItemMoved', handleItemMoved);

  // ✅ NOVO: Remover listener de delete
  emitter.off('kanbanItemDeleted', ({ itemId }) => {
    columnItems.value = columnItems.value.filter(
      item => Number(item.id) !== Number(itemId)
    );
  });

  // ✅ NOVO: Remover listener de movimento entre etapas
  emitter.off(
    'kanbanItemMovedBetweenStages',
    ({ itemId, fromStage, toStage, funnelId }) => {
      if (props.id === fromStage || props.id === toStage) {
        fetchStageStatsFromAPI(itemId);
      }
    }
  );
});

// Atualizar o watch para sincronizar as opções
watch(
  () => columnSettings.value.showAll,
  newValue => {
    if (newValue) {
      columnSettings.value.showWon = true;
      columnSettings.value.showLost = true;
    }
    saveColumnSettings();
  }
);

// Atualizar o watch para a opção "todos"
watch(
  [() => columnSettings.value.showWon, () => columnSettings.value.showLost],
  ([showWon, showLost]) => {
    columnSettings.value.showAll = showWon && showLost;
  }
);

const handleEditStage = () => {
  editingStageForm.value = {
    name: props.title,
    color: props.color,
    description: props.description || '',
  };
  showEditStageModal.value = true;
  showOptionsMenu.value = false;
};

const handleSaveStage = async () => {
  try {
    const funnel = store.getters['funnel/getSelectedFunnel'];
    const updatedStages = { ...funnel.stages };

    updatedStages[props.id] = {
      ...updatedStages[props.id],
      name: editingStageForm.value.name,
      color: editingStageForm.value.color,
      description: editingStageForm.value.description,
    };

    await FunnelAPI.update(funnel.id, {
      ...funnel,
      stages: updatedStages,
    });

    showEditStageModal.value = false;

    // Força atualização do store
    await store.dispatch('funnel/fetch');

    // REMOVIDO: emit('itemsUpdated') - deixe o store cuidar da sincronização

    // Notifica sucesso
    emitter.emit('newToastMessage', {
      message: 'Etapa atualizada com sucesso',
      action: { type: 'success' },
    });
  } catch (error) {
    console.error('Erro ao atualizar etapa:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao atualizar etapa',
      action: { type: 'error' },
    });
  }
};

// Nova função para colapsar ou expandir todos os itens da coluna
const toggleAllItems = () => {
  // Atualiza o estado local
  allItemsCollapsed.value = !allItemsCollapsed.value;

  // Carrega as informações de colapso existentes
  const collapsedItems = JSON.parse(
    localStorage.getItem('kanban_collapsed_items') || '{}'
  );

  // Atualiza o estado de todos os itens da coluna
  filteredItems.value.forEach(item => {
    collapsedItems[item.id] = allItemsCollapsed.value;
  });

  // Salva de volta no localStorage
  localStorage.setItem(
    'kanban_collapsed_items',
    JSON.stringify(collapsedItems)
  );

  // Fecha o menu de opções
  showOptionsMenu.value = false;

  // REMOVIDO: emit('itemsUpdated') - deixe o store cuidar da sincronização

  // Dispara um evento global para notificar os itens
  emitter.emit('kanbanItemsCollapsedStateChanged');
};

// New method to handle itemDragend from KanbanItem
const handleItemDragEndInColumn = item => {
  emit('itemDragend', item);
};

const showStageReportModal = ref(false);

// Adicionar função para expandir etapa
const handleExpandStage = () => {
  emit('expand', props.id);
  showOptionsMenu.value = false;
};
const handleCloseExpanded = () => {
  emit('closeExpanded');
  showOptionsMenu.value = false;
};

const PRIORITY_LABELS = [
  { key: 'urgent', label: 'Urgente' },
  { key: 'high', label: 'Alta' },
  { key: 'medium', label: 'Média' },
  { key: 'low', label: 'Baixa' },
  { key: 'none', label: 'Nenhuma' },
];

const itemsByPriority = computed(() => {
  const groups = {
    urgent: [],
    high: [],
    medium: [],
    low: [],
    none: [],
  };
  filteredItems.value.forEach(item => {
    const priority = item.item_details?.priority || 'none';
    if (groups[priority]) {
      groups[priority].push(item);
    } else {
      groups.none.push(item);
    }
  });
  return groups;
});

const filteredPriorityLabels = computed(() => {
  return PRIORITY_LABELS.filter(
    priority =>
      itemsByPriority.value[priority.key] &&
      itemsByPriority.value[priority.key].length > 0
  );
});

// Atualizar itens da coluna - REMOVIDO: não fazer refresh automático
const handleItemsUpdated = async () => {
  // Deixe o store e watchers cuidarem da sincronização
};

// Não carregar itens automaticamente - apenas reagir aos dados já carregados
</script>

<template>
  <div
    v-show="!columnSettings.hideColumn"
    class="kanban-column-root"
    :class="[
      props.isExpanded ? 'kanban-column-expanded' : '',
      props.isExpanded ? 'bg-slate-100 dark:bg-slate-800' : '',
    ]"
    :style="{ ...columnWidth, ...columnStyle }"
  >
    <div
      class="pl-4 pr-4 pt-2 pb-2"
      :style="{
        borderBottom: `1px solid ${props.color}59`,
        background: props.color ? `${props.color}40` : '#f8fafc',
      }"
      @contextmenu="handleHeaderContextMenu"
    >
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <h3
            class="text-sm font-medium"
            :style="{ color: textColor }"
            :title="props.title"
          >
            {{ props.title }}
          </h3>
          <span
            :key="`count-${props.id}-${columnCount}`"
            class="inline-flex items-center justify-center w-5 h-5 text-xs font-medium rounded-full"
            :style="countStyle"
          >
            {{ columnCount }}
          </span>
          <!-- Botão Carregar Mais no modo expandido -->
          <Button
            v-if="props.isExpanded && hasMorePages"
            variant="faded"
            size="xs"
            :is-loading="isLoadingMore"
            :style="{
              '--button-bg-color': props.color ? `${props.color}15` : '#FFF4E5',
              '--button-text-color': textColor,
              '--button-hover-bg-color': props.color
                ? `${props.color}25`
                : '#FFE4B3',
            }"
            class="custom-colored-button ml-2"
            @click="loadMoreItems"
          >
            {{ t('KANBAN.LOAD_MORE') }}
          </Button>
          <!-- Pilha de avatares dos agentes -->
          <div class="flex -space-x-2 ml-2">
            <template v-for="(agent, idx) in agentAvatars" :key="agent.id">
              <AgentTooltip :text="agent.name">
                <Avatar
                  :name="agent.name"
                  :src="agent.avatar_url"
                  :size="22"
                  :style="{ zIndex: 10 - idx }"
                />
              </AgentTooltip>
            </template>
            <span
              v-if="extraAgentsCount > 0"
              class="inline-flex items-center justify-center w-6 h-6 text-xs font-semibold bg-slate-200 dark:bg-slate-700 text-slate-700 dark:text-slate-200 rounded-full"
              style="z-index: 1; margin-left: -0.5rem"
            >
              +{{ extraAgentsCount }}
            </span>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <span
            v-if="formattedTotal && isStacklab && columnSettings.showTotal"
            class="text-xs font-medium relative group cursor-pointer"
            :style="{ color: textColor }"
            @mouseenter="showTotalTooltip = true"
            @mouseleave="showTotalTooltip = false"
          >
            {{ formattedTotalAbbreviated }}
            <span
              v-if="showTotalTooltip"
              class="absolute left-1/2 -translate-x-1/2 mt-2 px-3 py-2 rounded bg-slate-900 text-white text-xs font-medium shadow-lg z-50"
              style="
                top: 100%;
                min-width: max-content;
                pointer-events: none;
                white-space: pre-line;
              "
            >
              {{ allCurrenciesTooltip || formattedTotal }}
            </span>
          </span>
          <button
            class="p-1 text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-100"
            @click="$emit('add', id)"
          >
            <fluent-icon icon="add" size="16" />
          </button>
          <!-- Botão de mais opções -->
          <div class="relative">
            <button
              class="p-1 text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-100 options-menu-button"
              @click.stop="showOptionsMenu = !showOptionsMenu"
            >
              <fluent-icon icon="more-vertical" size="16" />
            </button>

            <!-- Menu de Opções -->
            <div
              v-if="showOptionsMenu"
              class="absolute right-0 top-full mt-1 bg-white dark:bg-slate-800 rounded-lg shadow-lg border border-slate-200 dark:border-slate-700 py-2 w-48 z-10 options-menu-content"
              @click.stop
            >
              <div class="px-4 py-2">
                <button
                  class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200 w-full hover:text-woot-500"
                  @click="handleEditStage"
                >
                  <fluent-icon icon="edit" size="16" />
                  <span>{{ t('KANBAN.COLUMN_OPTIONS.EDIT_STAGE') }}</span>
                </button>
              </div>
              <div
                class="border-t border-slate-100 dark:border-slate-700 my-1"
              />
              <div class="px-4 py-2">
                <label
                  class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200"
                >
                  <input
                    v-model="columnSettings.showAll"
                    type="checkbox"
                    class="form-checkbox"
                    @change="saveColumnSettings"
                  />
                  <span>{{ t('KANBAN.COLUMN_OPTIONS.SHOW_ALL') }}</span>
                </label>
              </div>
              <div class="px-4 py-2">
                <label
                  class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200"
                >
                  <input
                    v-model="columnSettings.showWon"
                    type="checkbox"
                    class="form-checkbox"
                    @change="saveColumnSettings"
                  />
                  <span>{{ t('KANBAN.COLUMN_OPTIONS.SHOW_WON') }}</span>
                </label>
              </div>
              <div class="px-4 py-2">
                <label
                  class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200"
                >
                  <input
                    v-model="columnSettings.showLost"
                    type="checkbox"
                    class="form-checkbox"
                    @change="saveColumnSettings"
                  />
                  <span>{{ t('KANBAN.COLUMN_OPTIONS.SHOW_LOST') }}</span>
                </label>
              </div>
              <div class="px-4 py-2">
                <label
                  class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200"
                >
                  <input
                    v-model="columnSettings.hideColumn"
                    type="checkbox"
                    class="form-checkbox"
                    @change="saveColumnSettings"
                  />
                  <span>{{ t('KANBAN.COLUMN_OPTIONS.HIDE_STAGE') }}</span>
                </label>
              </div>
              <div class="px-4 py-2">
                <button
                  class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200 w-full hover:text-woot-500"
                  @click="showSortModal = true"
                >
                  <fluent-icon icon="arrow-sort" size="16" />
                  <span>{{ t('KANBAN.COLUMN_OPTIONS.SORT') }}</span>
                </button>
              </div>
              <div
                class="border-t border-slate-100 dark:border-slate-700 my-1"
              />
              <div class="px-4 py-2">
                <button
                  class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200 w-full hover:text-woot-500"
                  @click="toggleAllItems"
                >
                  <fluent-icon
                    :icon="
                      allItemsCollapsed ? 'arrow-expand' : 'arrow-outwards'
                    "
                    size="16"
                  />
                  <span>{{
                    allItemsCollapsed
                      ? t('KANBAN.COLUMN_OPTIONS.EXPAND_ALL')
                      : t('KANBAN.COLUMN_OPTIONS.COLLAPSE_ALL')
                  }}</span>
                </button>
              </div>
              <div class="px-4 py-2">
                <button
                  class="text-sm text-slate-700 dark:text-slate-200 w-full hover:text-woot-500"
                  @click="showStageReportModal = true"
                >
                  {{ t('KANBAN.COLUMN_OPTIONS.STAGE_REPORT') }}
                </button>
              </div>
              <div class="px-4 py-2">
                <button
                  v-if="!props.isExpanded"
                  class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200 w-full hover:text-woot-500"
                  @click="handleExpandStage"
                >
                  {{ t('KANBAN.COLUMN_OPTIONS.EXPAND_STAGE') }}
                </button>
                <button
                  v-if="props.isExpanded"
                  class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200 w-full hover:text-woot-500"
                  @click="handleCloseExpanded"
                >
                  {{ t('KANBAN.COLUMN_OPTIONS.BACK_TO_KANBAN') }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div
      ref="scrollContainer"
      :class="
        props.isExpanded
          ? 'kanban-items-priority-columns'
          : 'flex-1 overflow-y-auto'
      "
      @drop="handleDrop"
      @dragover="handleDragOver"
      @dragleave="handleDragLeave"
    >
      <template v-if="props.isExpanded">
        <div class="priority-columns-wrapper">
          <div
            v-for="priority in filteredPriorityLabels"
            :key="priority.key"
            class="priority-column"
          >
            <div class="priority-header">
              <PriorityCircle
                :priority="priority.key"
                :size="20"
                class="mr-2"
              />
              <span class="priority-label">{{ priority.label }}</span>
              <span class="priority-count">{{
                itemsByPriority[priority.key].length
              }}</span>
            </div>
            <div class="priority-items priority-items-scroll">
              <KanbanItem
                v-for="item in itemsByPriority[priority.key]"
                :key="item.id"
                :item="item"
                :kanban-items="columnItems.value || []"
                force-expanded
                draggable
                @dragstart="
                  e => {
                    e.dataTransfer.setData('text/plain', item.id.toString());
                    $emit('itemDragstart', item);
                  }
                "
                @item-dragend="handleItemDragEndInColumn(item)"
                @click="
                  modifiedItem => {
                    $emit('itemClick', modifiedItem);
                  }
                "
                @edit="
                  modifiedItem => {
                    $emit('edit', modifiedItem);
                  }
                "
                @delete="$emit('delete', item)"
              />
            </div>
          </div>
        </div>
      </template>
      <template v-else>
        <div class="px-4">
          <div class="py-3 space-y-3">
            <template v-if="displayedItems.length">
              <template v-for="(item, index) in displayedItems" :key="item.id">
                <!-- Placeholder antes do item -->
                <div
                  v-if="isDraggingOver && dragPlaceholderIndex === index"
                  class="drag-placeholder"
                />

                <div class="kanban-item-wrapper">
                  <KanbanItem
                    :item="item"
                    :kanban-items="columnItems.value || []"
                    draggable
                    @dragstart="
                      e => {
                        e.dataTransfer.setData(
                          'text/plain',
                          item.id.toString()
                        );
                        $emit('itemDragstart', item);
                      }
                    "
                    @item-dragend="handleItemDragEndInColumn(item)"
                    @click="
                      modifiedItem => {
                        $emit('itemClick', modifiedItem);
                      }
                    "
                    @edit="
                      modifiedItem => {
                        $emit('edit', modifiedItem);
                      }
                    "
                    @delete="$emit('delete', item)"
                  />
                </div>
              </template>

              <!-- Placeholder no final da lista -->
              <div
                v-if="
                  isDraggingOver &&
                  dragPlaceholderIndex === displayedItems.length
                "
                class="drag-placeholder"
              />

              <!-- Botão Carregar Mais -->
              <div v-if="hasMorePages" class="flex justify-center py-3">
                <Button
                  variant="faded"
                  size="sm"
                  :is-loading="isLoadingMore"
                  :style="{
                    '--button-bg-color': props.color
                      ? `${props.color}15`
                      : '#FFF4E5',
                    '--button-text-color': textColor,
                    '--button-hover-bg-color': props.color
                      ? `${props.color}25`
                      : '#FFE4B3',
                  }"
                  class="custom-colored-button"
                  @click="loadMoreItems"
                >
                  {{ t('KANBAN.LOAD_MORE') }}
                </Button>
              </div>
            </template>

            <!-- Placeholder quando a coluna está vazia -->
            <div
              v-if="!displayedItems.length && isDraggingOver"
              class="drag-placeholder"
            />

            <div
              v-else-if="!displayedItems.length"
              class="flex items-center justify-center h-24 text-sm text-slate-500 dark:text-slate-400"
            >
              {{ t('KANBAN.NO_ITEMS') }}
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- Modal de Edição de Etapa -->
    <Modal
      v-model:show="showEditStageModal"
      :on-close="() => (showEditStageModal = false)"
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4">
          {{ t('KANBAN.EDIT_STAGE_MODAL.TITLE') }}
        </h3>

        <div class="space-y-4">
          <div>
            <label class="block text-sm font-medium mb-1">{{
              t('KANBAN.EDIT_STAGE_MODAL.NAME')
            }}</label>
            <input
              v-model="editingStageForm.name"
              type="text"
              class="w-full px-3 py-2 border rounded-lg"
              :placeholder="t('KANBAN.EDIT_STAGE_MODAL.NAME_PLACEHOLDER')"
            />
          </div>

          <div>
            <label class="block text-sm font-medium mb-1">{{
              t('KANBAN.EDIT_STAGE_MODAL.COLOR')
            }}</label>
            <StageColorPicker v-model="editingStageForm.color" />
          </div>

          <div>
            <label class="block text-sm font-medium mb-1">{{
              t('KANBAN.EDIT_STAGE_MODAL.DESCRIPTION')
            }}</label>
            <textarea
              v-model="editingStageForm.description"
              class="w-full px-3 py-2 border rounded-lg"
              rows="3"
              :placeholder="
                t('KANBAN.EDIT_STAGE_MODAL.DESCRIPTION_PLACEHOLDER')
              "
            />
          </div>

          <div class="flex justify-end gap-2">
            <Button
              variant="ghost"
              color="slate"
              size="sm"
              @click="showEditStageModal = false"
            >
              {{ t('KANBAN.ACTIONS.CANCEL') }}
            </Button>
            <Button
              variant="solid"
              color="blue"
              size="sm"
              @click="handleSaveStage"
            >
              {{ t('KANBAN.ACTIONS.SAVE') }}
            </Button>
          </div>
        </div>
      </div>
    </Modal>

    <!-- Modal de Ordenação -->
    <Modal
      v-model:show="showSortModal"
      :on-close="() => (showSortModal = false)"
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4">
          {{ t('KANBAN.SORT_MODAL.TITLE') }}
        </h3>

        <div class="space-y-4">
          <div>
            <label class="block text-sm font-medium mb-2">{{
              t('KANBAN.SORT_MODAL.SORT_BY')
            }}</label>
            <select
              v-model="columnSort.type"
              class="w-full px-3 py-2 border rounded-lg"
              @change="saveSortSettings"
            >
              <option
                v-for="option in sortOptions"
                :key="option.id"
                :value="option.id"
              >
                {{
                  t(
                    `KANBAN.SORT_OPTIONS.${option.id.toUpperCase()}`,
                    option.label
                  )
                }}
              </option>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium mb-2">{{
              t('KANBAN.SORT_MODAL.DIRECTION')
            }}</label>
            <div class="flex gap-4">
              <label class="flex items-center gap-2">
                <input
                  v-model="columnSort.direction"
                  type="radio"
                  value="asc"
                  @change="saveSortSettings"
                />
                <span class="text-sm">{{
                  t('KANBAN.SORT_MODAL.ASCENDING')
                }}</span>
              </label>
              <label class="flex items-center gap-2">
                <input
                  v-model="columnSort.direction"
                  type="radio"
                  value="desc"
                  @change="saveSortSettings"
                />
                <span class="text-sm">{{
                  t('KANBAN.SORT_MODAL.DESCENDING')
                }}</span>
              </label>
            </div>
          </div>

          <div class="flex justify-end gap-2">
            <Button
              variant="ghost"
              color="slate"
              size="sm"
              @click="showSortModal = false"
            >
              {{ t('KANBAN.FUNNELS.FORM.ACTIONS.CANCEL') }}
            </Button>
            <Button
              variant="solid"
              color="blue"
              size="sm"
              @click="showSortModal = false"
            >
              {{ t('KANBAN.FORM.APPLY') }}
            </Button>
          </div>
        </div>
      </div>
    </Modal>

    <!-- Context menu customizado do header -->
    <div
      v-if="showHeaderContextMenu"
      class="fixed z-50 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded shadow-lg py-1 px-0 min-w-[180px]"
      :style="{
        left: contextMenuPosition.x + 'px',
        top: contextMenuPosition.y + 'px',
      }"
      @click.stop
    >
      <button
        class="w-full text-left px-4 py-2 text-sm text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700"
        @click="toggleShowTotal"
      >
        {{
          columnSettings.showTotal
            ? t('KANBAN.COLUMN_OPTIONS.HIDE_OFFERS_TOTAL')
            : t('KANBAN.COLUMN_OPTIONS.SHOW_OFFERS_TOTAL')
        }}
      </button>
    </div>

    <!-- Modal de Relatório da Etapa -->
    <KanbanStageReport
      v-if="showStageReportModal"
      :title="props.title"
      :color="props.color"
      :description="props.description"
      :items="filteredItems"
      :on-close="() => (showStageReportModal = false)"
    />

    <!-- Borda de redimensionamento -->
    <div
      v-if="!props.isExpanded"
      class="resize-handle"
      :class="[{ resizing: isResizing }]"
      :title="t('KANBAN.COLUMN_RESIZE_TOOLTIP')"
      @mousedown="startResize"
      @dblclick="resetWidth"
    />
  </div>
</template>

<style lang="scss" scoped>
.kanban-column-root {
  display: flex;
  flex-direction: column;
  border-radius: 0.5rem;
  overflow: hidden;
  position: relative;
}
.kanban-column-expanded {
  width: 100% !important;
  min-width: 0 !important;
  max-width: 100% !important;
  margin: 0 !important;
  border-radius: 1rem !important;
  box-shadow: none !important;
  flex: 1 1 100%;
  box-sizing: border-box;
}
.kanban-items-priority-columns {
  display: flex;
  flex-direction: row;
  gap: 0;
  padding: 0;
  margin: 0;
  margin-top: 0.75rem;
  padding-left: 0.75rem;
  padding-right: 0.75rem;
  width: 100%;
  height: 100%;
  min-height: 0;
  box-sizing: border-box;
  overflow-y: auto;
  scrollbar-width: thin;
  scrollbar-color: #e5e7eb #f3f4f6;
}
.kanban-items-priority-columns::-webkit-scrollbar {
  width: 6px;
  background: #f3f4f6;
}
.kanban-items-priority-columns::-webkit-scrollbar-thumb {
  background: #e5e7eb;
  border-radius: 4px;
}

.dark .kanban-items-priority-columns {
  scrollbar-color: #475569 #334155;
}
.dark .kanban-items-priority-columns::-webkit-scrollbar {
  background: #334155;
}
.dark .kanban-items-priority-columns::-webkit-scrollbar-thumb {
  background: #475569;
}
.priority-columns-wrapper {
  display: flex;
  flex-direction: row;
  gap: 0;
  width: 100%;
  height: 100%;
  min-height: 0;
}
.priority-column {
  flex: 1 1 0;
  min-width: 0;
  background: transparent;
  border-radius: 0.5rem;
  padding: 0 0.5rem;
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
}
.priority-header {
  font-weight: 600;
  font-size: 1rem;
  margin-bottom: 1rem;
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.priority-label {
  color: #334155;
}

.dark .priority-label {
  color: #cbd5e1;
}

.priority-count {
  background: #e2e8f0;
  color: #334155;
  border-radius: 999px;
  font-size: 0.85rem;
  padding: 0.1rem 0.7rem;
  font-weight: 500;
}

.dark .priority-count {
  background: #475569;
  color: #cbd5e1;
}
.priority-items {
  display: flex;
  flex-direction: column;
  gap: 0.1rem; /* Espaçamento igual ao modo não expandido */
}
.priority-items-scroll {
  overflow-y: auto;
  max-height: 100%;
  flex: 1 1 0;
  min-height: 0;
  scrollbar-width: thin;
}
.priority-items-scroll::-webkit-scrollbar {
  width: 6px;
  background: #f3f4f6;
}
.priority-items-scroll::-webkit-scrollbar-thumb {
  background: #e5e7eb;
  border-radius: 4px;
}

.dark .priority-items-scroll::-webkit-scrollbar {
  background: #334155;
}
.dark .priority-items-scroll::-webkit-scrollbar-thumb {
  background: #475569;
}
.overflow-y-auto {
  min-height: 0;
  height: 100%;
  padding-bottom: 1px;
  scrollbar-width: thin;
  scrollbar-color: #e5e7eb #f3f4f6;

  &::-webkit-scrollbar {
    width: 6px;
    background: #f3f4f6;
  }

  &::-webkit-scrollbar-thumb {
    background: #e5e7eb;
    border-radius: 4px;
  }
}

.dark .overflow-y-auto {
  scrollbar-color: #475569 #334155;

  &::-webkit-scrollbar {
    background: #334155;
  }

  &::-webkit-scrollbar-thumb {
    background: #475569;
  }
}
.space-y-3 > :not([hidden]) ~ :not([hidden]) {
  margin-top: 0.75rem;
}
.space-y-3 > :last-child {
  margin-bottom: 0;
}
.form-checkbox {
  @apply rounded border-slate-300 text-woot-500 shadow-sm focus:border-woot-500 focus:ring focus:ring-woot-500 focus:ring-opacity-50;
}

.custom-colored-button {
  background-color: var(--button-bg-color) !important;
  color: var(--button-text-color) !important;
  border: 1px solid var(--button-bg-color) !important;
}

.custom-colored-button:hover:not(:disabled) {
  background-color: var(--button-hover-bg-color) !important;
  border-color: var(--button-hover-bg-color) !important;
}

.custom-colored-button:focus-visible {
  background-color: var(--button-hover-bg-color) !important;
  border-color: var(--button-hover-bg-color) !important;
}

.resize-handle {
  position: absolute;
  top: 0;
  right: 0;
  width: 4px;
  height: 100%;
  cursor: col-resize;
  background: transparent;
  transition: background 0.2s;
  z-index: 1;
}

.resize-handle:hover,
.resize-handle.resizing {
  background: rgba(59, 130, 246, 0.5);
}

.drag-placeholder {
  height: 120px;
  border: 2px dashed #3b82f6;
  background: rgba(59, 130, 246, 0.05);
  border-radius: 0.5rem;
  margin: 0.75rem 0;
  transition: all 0.2s ease;
  animation: pulse 1.5s ease-in-out infinite;
}

.dark .drag-placeholder {
  border-color: #60a5fa;
  background: rgba(96, 165, 250, 0.1);
}

@keyframes pulse {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.6;
  }
}

.kanban-item-wrapper {
  transition: transform 0.2s ease;
}
</style>
