<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import KanbanHeader from './KanbanHeader.vue';
import KanbanAPI from '../../../../api/kanban';
import Modal from '../../../../components/Modal.vue';
import KanbanItemForm from './KanbanItemForm.vue';
import KanbanItemDetails from './KanbanItemDetails.vue';
import AgentAPI from '../../../../api/agents';
import CalendarMonth from '../../../../components/ui/DatePicker/components/CalendarMonth.vue';
import CalendarYear from '../../../../components/ui/DatePicker/components/CalendarYear.vue';
import CalendarWeekLabel from '../../../../components/ui/DatePicker/components/CalendarWeekLabel.vue';
import { CALENDAR_PERIODS } from '../../../../components/ui/DatePicker/helpers/DatePickerHelper';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();
const isLoading = ref(false);
const error = ref(null);
const items = ref([]);
const agents = ref({});
const searchQuery = ref('');
const activeFilters = ref(null);
const filteredResults = ref({ total: 0, stages: {} });
const currentMonth = ref(new Date());
const selectedDate = ref(new Date());
const showAddModal = ref(false);
const showEventDetails = ref(false);
const selectedEvent = ref(null);
const viewMode = ref('month'); // month, week, day

// Novas refs para o controle do mini calendário
const miniCalendarView = ref('days'); // 'days', 'months', 'years'
const { MONTH: PERIOD_MONTH, YEAR: PERIOD_YEAR } = CALENDAR_PERIODS;

// Refs para controle do modal de detalhes
const showItemDetails = ref(false);
const selectedItem = ref(null);

// Adicionar ref para controlar o estado de drag & drop
const dragOverCell = ref(null);


// Adicionar nova ref para controlar a data selecionada no mini calendário
const selectedMiniDate = ref(new Date());

const showEditModal = ref(false);
const selectedItemToEdit = ref(null);

// Ref para controlar o estado do painel lateral
const isPanelOpen = ref(true);

const props = defineProps({
  currentView: {
    type: String,
    default: 'agenda',
  },
  columns: {
    type: Array,
    default: () => [],
  },
});

// Computed para converter stages do funil para o formato columns esperado
const funnelColumns = computed(() => {
  const selectedFunnel = store.getters['funnel/getSelectedFunnel'];
  if (!selectedFunnel?.stages) return [];

  // Converte o objeto stages para array de columns
  const columns = Object.entries(selectedFunnel.stages).map(([stageId, stageData]) => ({
    id: stageId,
    title: stageData.name,
    color: stageData.color,
    position: stageData.position,
    description: stageData.description,
  })).sort((a, b) => a.position - b.position);

  // Debug: verificar se as cores estão sendo extraídas corretamente
  console.log('[AgendaTab] Columns convertidas:', columns);

  return columns;
});

// Computed para usar as columns corretas (fallback para props se necessário)
const columnsToUse = computed(() => {
  return funnelColumns.value.length > 0 ? funnelColumns.value : props.columns;
});

const emit = defineEmits(['switch-view']);

// Computed para dias do mês atual
const daysInMonth = computed(() => {
  const year = currentMonth.value.getFullYear();
  const month = currentMonth.value.getMonth();
  const firstDay = new Date(year, month, 1);
  const lastDay = new Date(year, month + 1, 0);
  const days = [];

  // Adicionar dias do mês anterior para completar a primeira semana
  const firstDayOfWeek = firstDay.getDay();
  for (let i = firstDayOfWeek - 1; i >= 0; i--) {
    const date = new Date(year, month, -i);
    const events = getEventsForDate(date);
    // Marcar eventos que vêm do checklist
    events.forEach(event => {
      event.isFromChecklist = hasChecklistDueDateOnDate(event, date);
    });
    days.push({
      date,
      isCurrentMonth: false,
      events,
    });
  }

  // Adicionar dias do mês atual
  for (let date = 1; date <= lastDay.getDate(); date++) {
    const currentDate = new Date(year, month, date);
    const events = getEventsForDate(currentDate);
    // Marcar eventos que vêm do checklist
    events.forEach(event => {
      event.isFromChecklist = hasChecklistDueDateOnDate(event, currentDate);
    });
    days.push({
      date: currentDate,
      isCurrentMonth: true,
      events,
    });
  }

  // Adicionar dias do próximo mês para completar a última semana
  const remainingDays = 42 - days.length; // 6 semanas * 7 dias = 42
  for (let i = 1; i <= remainingDays; i++) {
    const date = new Date(year, month + 1, i);
    const events = getEventsForDate(date);
    // Marcar eventos que vêm do checklist
    events.forEach(event => {
      event.isFromChecklist = hasChecklistDueDateOnDate(event, date);
    });
    days.push({
      date,
      isCurrentMonth: false,
      events,
    });
  }

  return days;
});

// Adicionar computed para dias baseado no modo de visualização
const visibleDays = computed(() => {
  if (viewMode.value === 'week') {
    const weekDays = getWeekDays();
    // Marcar eventos que vêm do checklist para a semana
    weekDays.forEach(day => {
      day.events.forEach(event => {
        event.isFromChecklist = hasChecklistDueDateOnDate(event, day.date);
      });
    });
    return weekDays;
  }
  return daysInMonth.value;
});

// Função para obter os dias da semana atual
const getWeekDays = () => {
  const today = selectedDate.value || new Date();
  const start = new Date(today);
  start.setDate(start.getDate() - start.getDay()); // Começa no domingo

  const days = [];
  for (let i = 0; i < 7; i++) {
    const date = new Date(start);
    date.setDate(start.getDate() + i);
    days.push({
      date,
      isCurrentMonth: date.getMonth() === currentMonth.value.getMonth(),
      events: getEventsForDate(date),
    });
  }
  return days;
};

// Atualizar o computed weeks para usar visibleDays
const weeks = computed(() => {
  const days =
    viewMode.value === 'week' ? visibleDays.value : daysInMonth.value;
  const weeks = [];
  for (let i = 0; i < days.length; i += 7) {
    weeks.push(days.slice(i, i + 7));
  }
  return weeks;
});

// Computed para nomes dos dias da semana
const weekDays = computed(() => {
  const days = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
  return days;
});

// Função auxiliar para verificar se item tem due_date do checklist na data
const hasChecklistDueDateOnDate = (item, date) => {
  const compareYear = date.getFullYear();
  const compareMonth = date.getMonth();
  const compareDay = date.getDate();

  const checklist = item.checklist || [];
  // Garantir que checklist seja um array
  const checklistArray = Array.isArray(checklist) ? checklist : [];
  return checklistArray.some(checklistItem => {
    const dueDate = checklistItem.due_date;
    if (!dueDate) return false;

    const checklistDate = new Date(dueDate);
    return (
      checklistDate.getFullYear() === compareYear &&
      checklistDate.getMonth() === compareMonth &&
      checklistDate.getDate() === compareDay
    );
  });
};

// Atualizar a função getEventsForDate para usar o horário local
const getEventsForDate = date => {
  const compareYear = date.getFullYear();
  const compareMonth = date.getMonth();
  const compareDay = date.getDate();

  const events = [];

  items.value.forEach(item => {
    // Verifica scheduled_at ou deadline_at do item
    const itemDate =
      item.item_details?.scheduled_at || item.item_details?.deadline_at;
    if (itemDate) {
      const eventDate = new Date(itemDate);
      if (
        eventDate.getFullYear() === compareYear &&
        eventDate.getMonth() === compareMonth &&
        eventDate.getDate() === compareDay
      ) {
        events.push({
          ...item,
          isFromChecklist: false,
          checklistItem: null,
        });
      }
    }

    // Verifica due_date dos itens do checklist
    if (hasChecklistDueDateOnDate(item, date)) {
      // Para cada item do checklist que tem due_date nesta data, cria um evento separado
      const checklist = item.checklist || [];
      // Garantir que checklist seja um array
      const checklistArray = Array.isArray(checklist) ? checklist : [];
      checklistArray.forEach(checklistItem => {
        const dueDate = checklistItem.due_date;
        if (!dueDate) return;

        const checklistDate = new Date(dueDate);
        if (
          checklistDate.getFullYear() === compareYear &&
          checklistDate.getMonth() === compareMonth &&
          checklistDate.getDate() === compareDay
        ) {
          events.push({
            ...item,
            isFromChecklist: true,
            checklistItem: checklistItem,
          });
        }
      });
    }
  });

  return events;
};

// Adicionar função para navegar entre semanas
const changeWeek = direction => {
  const newDate = new Date(selectedDate.value);
  newDate.setDate(newDate.getDate() + direction * 7);
  selectedDate.value = newDate;
  currentMonth.value = new Date(newDate); // Atualiza o mês se necessário
};

// Atualizar a função de mudança de mês para considerar o modo
const changeMonth = direction => {
  if (viewMode.value === 'week') {
    changeWeek(direction * 4); // Aproximadamente um mês
    return;
  }

  const newMonth = new Date(currentMonth.value);
  newMonth.setMonth(newMonth.getMonth() + direction);
  currentMonth.value = newMonth;
  selectedDate.value = newMonth;
};

// Atualizar a função formatDate para aceitar opções
const formatDate = (date, options = { month: 'long', year: 'numeric' }) => {
  const formatted = new Intl.DateTimeFormat('pt-BR', {
    ...options,
  }).format(date);

  // Garantir que a primeira letra seja maiúscula
  return formatted.charAt(0).toUpperCase() + formatted.slice(1);
};

// Função para verificar se é hoje
const isToday = date => {
  const today = new Date();
  return (
    date.getDate() === today.getDate() &&
    date.getMonth() === today.getMonth() &&
    date.getFullYear() === today.getFullYear()
  );
};

// Adicionar o computed para eventos do dia
const todayEvents = computed(() => {
  const today = new Date();
  return items.value
    .filter(item => {
      const itemDate =
        item.item_details?.scheduling_type === 'deadline'
          ? item.item_details?.deadline_at
          : item.item_details?.scheduled_at;

      if (!itemDate) return false;

      const eventDate = new Date(itemDate);

      return (
        eventDate.getUTCFullYear() === today.getFullYear() &&
        eventDate.getUTCMonth() === today.getMonth() &&
        eventDate.getUTCDate() === today.getDate()
      );
    })
    .sort((a, b) => {
      const dateA = new Date(
        a.item_details?.scheduling_type === 'deadline'
          ? a.item_details?.deadline_at
          : a.item_details?.scheduled_at
      );
      const dateB = new Date(
        b.item_details?.scheduling_type === 'deadline'
          ? b.item_details?.deadline_at
          : b.item_details?.scheduled_at
      );
      return dateA - dateB;
    });
});

// Atualizar a função para converter UTC para horário local
const toLocalTime = date => {
  if (!date) return null;
  try {
    const utcDate = new Date(date);
    // Extrair apenas o horário no formato HH:mm
    return `${String(utcDate.getHours()).padStart(2, '0')}:${String(
      utcDate.getMinutes()
    ).padStart(2, '0')}`;
  } catch (error) {
    console.error('Erro ao converter data:', error);
    return null;
  }
};

// Simplificar para mostrar apenas o título do evento
const formatEventTime = date => {
  if (!date) return '';
  return ''; // Não exibir horário
};

// Removido: lógica de posicionamento por horário


// Adicionar computed para formatar valor
const formatValue = value => {
  if (!value) return null;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(value);
};

// Adicionar função para buscar dados do agente
const fetchAgentDetails = async agentId => {
  if (!agentId) return null;
  if (agents.value[agentId]) return agents.value[agentId];

  try {
    // Buscar todos os agentes se ainda não tivermos buscado
    if (Object.keys(agents.value).length === 0) {
      const { data } = await AgentAPI.get();
      // Mapear os agentes por ID para acesso mais rápido
      data.forEach(agent => {
        agents.value[agent.id] = agent;
      });
    }

    return agents.value[agentId] || null;
  } catch (error) {
    console.error('Erro ao carregar agente:', error);
    return null;
  }
};

// Atualizar a função fetchKanbanItems
const fetchKanbanItems = async ({ showLoading = true } = {}) => {
  try {
    if (showLoading) {
      isLoading.value = true;
    }

    // Carregar todos os agentes primeiro para evitar requisições repetidas.
    if (Object.keys(agents.value).length === 0) {
      const { data } = await AgentAPI.get();
      data.forEach(agent => {
        agents.value[agent.id] = agent;
      });
    }

    // Buscar todos os itens paginados para a agenda
    const selectedFunnel = store.getters['funnel/getSelectedFunnel'];
    if (!selectedFunnel) {
      console.error('Nenhum funil selecionado');
      items.value = [];
      return;
    }

    // Buscar todos os itens do funil sem filtros de stage ou agent para a agenda
    let allItems = [];
    let page = 1;
    let hasMore = true;

    while (hasMore) {
      const response = await KanbanAPI.getItems(selectedFunnel.id, page);
      const responseData = response.data;
      
      if (responseData && responseData.items) {
        // Nova estrutura paginada
        allItems = allItems.concat(responseData.items);
        hasMore = responseData.pagination?.has_more || false;
      } else if (Array.isArray(responseData)) {
        // Estrutura antiga (array direto)
        allItems = responseData;
        hasMore = false;
      } else {
        // Resposta vazia ou inválida
        hasMore = false;
      }
      
      page++;
      
      // Proteção contra loop infinito
      if (page > 100) {
        console.warn('Limite de páginas atingido, interrompendo busca');
        break;
      }
    }

    let apiData = allItems;

    // Mapear os itens e buscar dados dos agentes
    const itemsWithAgents = await Promise.all(
      apiData.map(async item => {
        const agentId = item.item_details?.agent_id;
        const agent = agentId ? agents.value[agentId] : null;
        
        // Estruturar assigned_agents como KanbanItem.vue espera
        let assignedAgents = [];
        if (item.assigned_agents && item.assigned_agents.length > 0) {
          // Se já tem assigned_agents da API, usar eles
          assignedAgents = item.assigned_agents;
        } else if (agent) {
          // Criar assigned_agents baseado no agente único (compatibilidade)
          assignedAgents = [{
            id: agent.id,
            name: agent.name,
            avatar_url: agent.avatar_url || agent.thumbnail || '',
            assigned_at: null,
            assigned_by: null,
          }];
        }

        return {
          id: item.id,
          title: item.item_details?.title || '',
          description: item.item_details?.description || '',
          priority: item.item_details?.priority || 'none',
          funnel_id: item.funnel_id,
          funnel_stage: item.funnel_stage,
          position: item.position,
          
          // Dados importantes que podem ser perdidos
          stage_entered_at: item.stage_entered_at || null,
          conversation_display_id: item.conversation_display_id || null,
          assigned_agents: assignedAgents,
          checklist: item.checklist || [],
          conversation: item.conversation || null,
          
          item_details: {
            ...item.item_details,
            _agent: agent,
          },
          
          stageName:
            columnsToUse.value.find(col => col.id === item.funnel_stage)?.title ||
            '',
          stageColor: (() => {
            const color = columnsToUse.value.find(col => col.id === item.funnel_stage)?.color || '#64748B';
            console.log(`[AgendaTab] Item ${item.id} - Stage: ${item.funnel_stage}, Color: ${color}`);
            return color;
          })(),
          created_at: item.created_at,
          custom_attributes: item.custom_attributes || {},
          
          // Dados do agente para compatibilidade
          agent: agent || null,
        };
      })
    );

    items.value = itemsWithAgents;
  } catch (e) {
    console.error('Erro ao carregar itens:', e);
    error.value = t('KANBAN.ERRORS.FETCH_ITEMS');
  } finally {
    isLoading.value = false;
  }
};
// Handlers
const handleViewChange = view => {
  emit('switch-view', view);
};

const handleDateClick = (date, events) => {
  selectedDate.value = date;
  showAddModal.value = true;
};

const handleFilter = filters => {
  activeFilters.value = filters;
};

const handleSearch = query => {
  searchQuery.value = query;
};

const handleItemCreated = async item => {
  if (!item) return;
  showAddModal.value = false;
  await fetchKanbanItems({ showLoading: false });
};

// Função para preparar item para detalhes - com dados completos como KanbanItem
const prepareItemForDetails = item => {
  // Buscar dados completos do item original
  const fullItem = items.value.find(i => i.id === item.id) || item;
  
  // Usar as novas funções de agente para garantir compatibilidade total com KanbanItem
  const agentInfo = getAgentInfo(fullItem);
  const primaryAgent = getPrimaryAgent(fullItem);
  
  return {
    id: fullItem.id || null,
    title: fullItem.item_details?.title || fullItem.title || '',
    description: fullItem.item_details?.description || fullItem.description || '',
    priority: fullItem.item_details?.priority || fullItem.priority || 'none',
    funnel_id: fullItem.funnel_id || null,
    funnel_stage: fullItem.funnel_stage || null,
    position: fullItem.position || 0,
    
    // Dados importantes que estavam sendo perdidos
    stage_entered_at: fullItem.stage_entered_at || null,
    conversation_display_id: fullItem.conversation_display_id || null,
    assigned_agents: fullItem.assigned_agents || [],
    
    item_details: {
      ...{
        title: fullItem.item_details?.title || fullItem.title || '',
        description: fullItem.item_details?.description || fullItem.description || '',
        priority: fullItem.item_details?.priority || fullItem.priority || 'none',
        value: null,
        currency: 'BRL',
        deadline_at: null,
        scheduling_type: null,
        scheduled_at: null,
        agent_id: primaryAgent?.id || null,
        rescheduled: false,
        rescheduling_history: [],
        notes: [],
        activities: [],
        conversation_id: null,
      },
      ...(fullItem.item_details || {}),
      _agent: primaryAgent, // Usar primaryAgent das novas funções
    },
    
    stageName: fullItem.stageName || columnsToUse.value.find(col => col.id === fullItem.funnel_stage)?.title || '',
    stageColor: fullItem.stageColor || columnsToUse.value.find(col => col.id === fullItem.funnel_stage)?.color || '#64748B',
    created_at: fullItem.created_at || new Date().toISOString(),
    custom_attributes: fullItem.custom_attributes || {},
    checklist: fullItem.checklist || [],
    
    // Dados do agente - usar primaryAgent para garantir compatibilidade com KanbanItem
    agent: primaryAgent || fullItem.agent || null,
    
    // Dados da conversa se disponível
    conversation: fullItem.conversation || null,
  };
};

// Função para abrir detalhes do item
const handleEventClick = event => {
  if (!event || !event.id) {
    return;
  }
  
  selectedItem.value = prepareItemForDetails(event);
  showItemDetails.value = true;
};

// Função para fechar detalhes do item
const handleCloseDetails = () => {
  showItemDetails.value = false;
  selectedItem.value = null;
};

// Atualizar a função handleCardDrop para armazenar datas de remarcação
const handleCardDrop = async (itemId, date, isReschedule = false) => {
  try {
    const item = items.value.find(i => i.id === itemId);
    if (!item) return;

    // Obter a data atual do item antes da remarcação
    const currentDate =
      item.item_details?.scheduling_type === 'deadline'
        ? item.item_details?.deadline_at
        : item.item_details?.scheduled_at;

    // Criar uma cópia do item_details para não modificar o original
    const updatedItemDetails = {
      ...item.item_details,
      scheduling_type: 'deadline',
      deadline_at: new Date(date).toISOString().split('T')[0],
      rescheduled: isReschedule,
      rescheduling_history: isReschedule
        ? [
            ...(item.item_details.rescheduling_history || []),
            {
              from_date: currentDate,
              to_date: new Date(date).toISOString().split('T')[0],
              changed_at: new Date().toISOString(),
            },
          ]
        : [],
    };

    const payload = {
      funnel_id: item.funnel_id,
      funnel_stage: item.funnel_stage,
      position: item.position,
      item_details: updatedItemDetails,
      custom_attributes: item.custom_attributes || {},
    };

    await KanbanAPI.updateItem(itemId, payload);
    await fetchKanbanItems();
  } catch (error) {
    console.error('Erro ao definir prazo:', error);
  }
};

// Atualizar as funções de drag & drop
const allowDrop = (e, date) => {
  e.preventDefault();
  dragOverCell.value = date;
};

const handleDragLeave = () => {
  dragOverCell.value = null;
};

const handleDrop = async (e, date) => {
  e.preventDefault();
  const itemId = parseInt(e.dataTransfer.getData('itemId'), 10);
  const isReschedule = e.dataTransfer.getData('isReschedule') === 'true';
  if (!itemId) return;

  dragOverCell.value = null;
  await handleCardDrop(itemId, date, isReschedule);
};


// Adicione esta função para lidar com a edição
const handleItemEdit = item => {
  selectedItemToEdit.value = {
    ...item,
    funnel_stage:
      item.funnel_stage ||
      store.getters['funnel/getSelectedFunnel']?.default_stage,
  };
  showEditModal.value = true;
};

// Adicione esta função para lidar com o item atualizado
const handleItemUpdated = async item => {
  showEditModal.value = false;
  selectedItemToEdit.value = null;
  showItemDetails.value = false;
  await fetchKanbanItems({ showLoading: false });
};

// Lifecycle hooks
onMounted(async () => {
  await fetchKanbanItems();
});

// Watch para atualizar quando o funil mudar
watch(
  () => store.getters['funnel/getSelectedFunnel'],
  async () => {
    await fetchKanbanItems();
  }
);

// Adicionar watch para o viewMode
watch(viewMode, newMode => {
  if (newMode === 'week') {
    selectedDate.value = new Date(); // Reset para a semana atual
  }
});


// Adicionar computed para eventos do dia selecionado
const selectedDayEvents = computed(() => {
  return items.value
    .filter(item => {
      const itemDate =
        item.item_details?.scheduling_type === 'deadline'
          ? item.item_details?.deadline_at
          : item.item_details?.scheduled_at;

      if (!itemDate) return false;

      const eventDate = new Date(itemDate);
      return (
        eventDate.getUTCFullYear() === selectedMiniDate.value.getFullYear() &&
        eventDate.getUTCMonth() === selectedMiniDate.value.getMonth() &&
        eventDate.getUTCDate() === selectedMiniDate.value.getDate()
      );
    })
    .sort((a, b) => {
      const dateA = new Date(
        a.item_details?.scheduled_at || a.item_details?.deadline_at
      );
      const dateB = new Date(
        b.item_details?.scheduled_at || b.item_details?.deadline_at
      );
      return dateA - dateB;
    });
});

// Função auxiliar para comparar se duas datas são o mesmo dia
const isSameDay = (date1, date2) => {
  return (
    date1.getFullYear() === date2.getFullYear() &&
    date1.getMonth() === date2.getMonth() &&
    date1.getDate() === date2.getDate()
  );
};

// Removido: computed para time-slotted events

// Handlers para os novos componentes do mini calendário
const openMiniCalendarMonthView = () => {
  miniCalendarView.value = 'months';
};

const handleMiniCalendarSetView = (calendarType, period) => {
  if (period === PERIOD_YEAR) {
    miniCalendarView.value = 'years';
  } else if (period === PERIOD_MONTH) {
    miniCalendarView.value = 'months';
  } else {
    miniCalendarView.value = 'days';
  }
};

const handleMiniCalendarSelectMonth = monthIndex => {
  const newDate = new Date(currentMonth.value);
  newDate.setMonth(monthIndex);
  currentMonth.value = newDate;
  selectedMiniDate.value = new Date(newDate); // Sincronizar selectedMiniDate
  miniCalendarView.value = 'days';
};

const handleMiniCalendarSelectYear = year => {
  const newDate = new Date(currentMonth.value);
  newDate.setFullYear(year);
  currentMonth.value = newDate;
  selectedMiniDate.value = new Date(newDate); // Sincronizar selectedMiniDate
  miniCalendarView.value = 'months'; // Mudar para visualização de meses após selecionar o ano
};

const handleMiniCalendarPrev = () => {
  // Usado por CalendarMonth para navegar para o ano anterior
  const newDate = new Date(currentMonth.value);
  newDate.setFullYear(newDate.getFullYear() - 1);
  currentMonth.value = newDate;
  selectedMiniDate.value = new Date(newDate);
};

const handleMiniCalendarNext = () => {
  // Usado por CalendarMonth para navegar para o próximo ano
  const newDate = new Date(currentMonth.value);
  newDate.setFullYear(newDate.getFullYear() + 1);
  currentMonth.value = newDate;
  selectedMiniDate.value = new Date(newDate);
};

// Computed para informações do agente - replicando funcionalidade do KanbanItem
const getAgentInfo = (item) => {
  // Prioriza assigned_agents se existir e tiver conteúdo
  if (item.assigned_agents && item.assigned_agents.length > 0) {
    return item.assigned_agents.map(agent => ({
      id: agent.id,
      name: agent.name,
      avatar_url: agent.avatar_url || agent.thumbnail || '',
      assigned_at: agent.assigned_at || null,
      assigned_by: agent.assigned_by || null,
    }));
  }
  
  // Fallback para agente único se disponível
  if (item.agent || item.item_details?._agent) {
    const agent = item.agent || item.item_details._agent;
    return [{
      id: agent.id,
      name: agent.name,
      avatar_url: agent.avatar_url || agent.thumbnail || '',
      assigned_at: null,
      assigned_by: null,
    }];
  }
  
  // Retorna array vazio se não houver agente
  return [];
};

// Computed para obter o agente principal - replicando funcionalidade do KanbanItem
const getPrimaryAgent = (item) => {
  const agentInfo = getAgentInfo(item);
  return agentInfo.length > 0 ? agentInfo[0] : null;
};

// Função de debug para logs no template
const debugLog = (message, ...args) => {
  console.log(`[DEBUG] ${message}`, ...args);
  return ''; // Retorna string vazia para não afetar o template
};

// Função para inspecionar elementos DOM
const inspectElement = (element, name) => {
  if (element) {
    const rect = element.getBoundingClientRect();
    console.log(`[INSPECT] ${name} - Top: ${rect.top}, Height: ${rect.height}, Padding: ${getComputedStyle(element).padding}`);
  }
  return '';
};

// Função para alternar o estado do painel lateral
const togglePanel = () => {
  console.log('Toggle panel - before:', isPanelOpen.value);
  isPanelOpen.value = !isPanelOpen.value;
  console.log('Toggle panel - after:', isPanelOpen.value);
};
</script>

<template>
  <div class="flex flex-col h-full bg-white dark:bg-slate-900">
    <KanbanHeader
      :current-view="currentView"
      :search-results="filteredResults"
      :active-filters="activeFilters"
      :columns="columnsToUse"
      :kanban-items="items"
      @switch-view="handleViewChange"
      @filter="handleFilter"
      @search="handleSearch"
    />

    <div class="flex flex-1 min-h-0 flex-col">
      <div class="flex flex-1 min-h-0">
        <!-- Mini Calendar Sidebar -->
        <div
          v-show="isPanelOpen"
          class="w-[280px] border-r border-slate-200 dark:border-slate-700 flex flex-col mini-calendar-section overflow-hidden"
        >
          <div class="p-4 flex-shrink-0 flex flex-col h-full">
            <!-- Mini Calendar Label -->
            <div class="mb-2">
              <span class="text-xs font-medium text-slate-500 dark:text-slate-400">
                {{ t('KANBAN.AGENDA.SELECT_MONTH') }}
              </span>
            </div>
            <!-- Mini Calendar Header -->
            <div
              v-if="miniCalendarView === 'days'"
              class="flex items-center justify-between mb-4"
            >
              <span
                class="text-sm font-medium text-slate-600 dark:text-slate-300 cursor-pointer hover:text-woot-500 dark:hover:text-woot-400"
                @click="openMiniCalendarMonthView"
              >
                {{ formatDate(currentMonth) }}
              </span>
              <div class="flex items-center gap-1">
                <Button
                  variant="ghost"
                  size="sm"
                  @click="changeMonth(-1)"
                >
                  <fluent-icon icon="chevron-left" size="12" />
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  @click="changeMonth(1)"
                >
                  <fluent-icon icon="chevron-right" size="12" />
                </Button>
              </div>
            </div>

            <!-- CalendarMonth View -->
            <CalendarMonth
              v-if="miniCalendarView === 'months'"
              calendar-type="start"
              :start-current-date="currentMonth"
              :end-current-date="currentMonth"
              class="mb-4"
              @select-month="handleMiniCalendarSelectMonth"
              @set-view="handleMiniCalendarSetView"
              @prev="handleMiniCalendarPrev"
              @next="handleMiniCalendarNext"
            />

            <!-- CalendarYear View -->
            <CalendarYear
              v-if="miniCalendarView === 'years'"
              calendar-type="start"
              :start-current-date="currentMonth"
              :end-current-date="currentMonth"
              class="mb-4"
              @select-year="handleMiniCalendarSelectYear"
              @prev="() => {}"
              @next="() => {}"
            />

            <!-- Mini Calendar Grid (apenas se a visualização for 'days') -->
            <div
              v-if="miniCalendarView === 'days'"
              class="mini-calendar mb-6 flex-shrink-0"
            >
              <!-- Mini Week Days - Substituído por CalendarWeekLabel -->
              <CalendarWeekLabel class="mb-2" />

              <!-- Mini Days Grid -->
              <div class="grid grid-cols-7 gap-2">
                <div
                  v-for="day in daysInMonth"
                  :key="day.date"
                  class="aspect-square flex items-center justify-center text-sm rounded-full cursor-pointer"
                  :class="{
                    'bg-slate-100 dark:bg-slate-800': !day.isCurrentMonth,
                    'bg-white dark:bg-slate-900': day.isCurrentMonth,
                    'text-slate-400': !day.isCurrentMonth,
                    'text-slate-900 dark:text-slate-100': day.isCurrentMonth,
                    'bg-woot-500 text-white':
                      isToday(day.date) && !day.events.length,
                    'ring-1 ring-woot-500': isSameDay(
                      day.date,
                      selectedMiniDate
                    ),
                    relative: day.events.length > 0,
                  }"
                  @click="selectedMiniDate = day.date"
                >
                  {{ day.date.getDate() }}
                  <!-- Indicador de eventos -->
                  <div
                    v-if="day.events.length > 0"
                    class="absolute -bottom-1 left-1/2 -translate-x-1/2 w-1.5 h-1.5 rounded-full bg-woot-500"
                  />
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Main Calendar -->
        <div class="flex-1 flex flex-col min-h-0">
          <!-- Main Calendar Header -->
          <div class="flex-shrink-0 bg-white dark:bg-slate-900">
            <div class="flex items-center justify-between px-4 py-4">
              <div class="flex items-center gap-2">
                <Button
                  variant="ghost"
                  size="sm"
                  @click="togglePanel"
                >
                  <svg v-if="isPanelOpen" xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-panel-right-open-icon lucide-panel-right-open opacity-50 text-slate-500">
                    <rect width="18" height="18" x="3" y="3" rx="2"/>
                    <path d="M15 3v18"/>
                    <path d="m10 15-3-3 3-3"/>
                  </svg>
                  <svg v-else xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-panel-right-close-icon lucide-panel-right-close opacity-50 text-slate-500">
                    <rect width="18" height="18" x="3" y="3" rx="2"/>
                    <path d="M15 3v18"/>
                    <path d="m8 9 3 3-3 3"/>
                  </svg>
                </Button>
                <h2
                  class="text-xl font-semibold text-slate-800 dark:text-slate-200"
                >
                  {{
                    formatDate(viewMode === 'week' ? selectedDate : currentMonth)
                  }}
                </h2>
              </div>
              <div class="flex items-center gap-2">
                <Button
                  variant="ghost"
                  color="slate"
                  size="sm"
                  @click="
                    selectedDate = new Date();
                    currentMonth = new Date();
                  "
                >
                  {{ t('KANBAN.AGENDA.VIEW_MODES.TODAY') }}
                </Button>
                <div
                  class="flex border border-slate-200 dark:border-slate-700 rounded-lg overflow-hidden"
                >
                  <Button
                    variant="ghost"
                    size="sm"
                    class="px-3 py-1.5 border-r border-slate-200 dark:border-slate-700 rounded-none"
                    :color="viewMode === 'month' ? 'blue' : 'slate'"
                    :class="{
                      'bg-slate-100 dark:bg-slate-800 text-woot-600 dark:text-woot-400':
                        viewMode === 'month',
                      'text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800/50':
                        viewMode !== 'month',
                    }"
                    @click="viewMode = 'month'"
                  >
                    {{ t('KANBAN.AGENDA.VIEW_MODES.MONTH') }}
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    class="px-3 py-1.5 rounded-none"
                    :color="viewMode === 'week' ? 'blue' : 'slate'"
                    :class="{
                      'bg-slate-100 dark:bg-slate-800 text-woot-600 dark:text-woot-400':
                        viewMode === 'week',
                      'text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800/50':
                        viewMode !== 'week',
                    }"
                    @click="viewMode = 'week'"
                  >
                    {{ t('KANBAN.AGENDA.VIEW_MODES.WEEK') }}
                  </Button>
                </div>
              </div>
            </div>

            <!-- Week Days Header -->
            <div
              class="border-b border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800/50"
              :class="viewMode === 'week' ? 'flex' : 'grid grid-cols-7'"
            >
              <div
                v-for="day in weekDays"
                :key="day"
                class="py-2.5 text-xs font-medium text-slate-600 dark:text-slate-400 text-center border-r last:border-r-0 border-slate-200 dark:border-slate-700 flex-1"
              >
                {{ day }}
              </div>
            </div>
          </div>

          <!-- Calendar Grid -->
          <div
            class="calendar-grid flex-1 overflow-y-auto"
            :data-view-mode="viewMode"
          >
            <div
              v-for="week in weeks"
              :key="week[0].date"
              :class="viewMode === 'week' ? 'flex' : 'grid grid-cols-7'"
            >

              <div
                v-for="day in week"
                :key="day.date"
                class="calendar-day relative last:border-r-0 flex-1"
                :class="[
                  viewMode === 'week' ? 'p-0' : 'p-2',
                  {
                    'bg-slate-50 dark:bg-slate-800/50': !day.isCurrentMonth,
                    'bg-white dark:bg-slate-800': day.isCurrentMonth,
                    today: isToday(day.date),
                    'h-full': viewMode === 'week',
                    'flex flex-col h-full': viewMode === 'week',
                  }
                ]"
                @click="handleDateClick(day.date, day.events)"
                @dragover="e => allowDrop(e, day.date)"
                @dragleave="handleDragLeave"
                @drop="e => handleDrop(e, day.date)"
              >
                <div class="h-full flex flex-col">
                  <!-- Date number at the top -->
                  <div class="flex justify-start p-2 pb-1">
                    <span
                      :class="[
                        'text-xs',
                        {
                          'text-slate-400 dark:text-slate-600': !day.isCurrentMonth,
                          'text-slate-900 dark:text-slate-100': day.isCurrentMonth,
                          'bg-woot-500 text-white rounded-full w-6 h-6 flex items-center justify-center':
                            isToday(day.date),
                        }
                      ]"
                    >
                      {{ day.date.getDate() }}
                    </span>
                  </div>

                  <!-- Events container below the date -->
                  <div class="flex-1 px-2 pb-2 overflow-hidden">
                    <!-- Events for week view -->
                    <template v-if="viewMode === 'week'">
                      <div class="day-events-container space-y-1">
                        <div
                          v-for="event in day.events"
                          :key="event.id"
                          class="event-item text-xs px-2 py-1 rounded truncate cursor-pointer hover:opacity-90"
                          :style="{
                            backgroundColor: event.isFromChecklist ? '#f1f5f9' : event.stageColor + '40',
                            color: event.isFromChecklist ? '#64748b' : event.stageColor,
                            borderLeft: `2px solid ${event.isFromChecklist ? '#cbd5e1' : event.stageColor}`,
                          }"
                          @click.stop="handleEventClick(event)"
                        >
                          <div class="flex items-center gap-1.5">
                            <svg
                              v-if="event.isFromChecklist"
                              xmlns="http://www.w3.org/2000/svg"
                              width="10"
                              height="10"
                              viewBox="0 0 24 24"
                              fill="none"
                              stroke="currentColor"
                              stroke-width="2.5"
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              class="lucide lucide-list-check-icon lucide-list-check flex-shrink-0 opacity-80"
                            >
                              <path d="M16 5H3"/>
                              <path d="M16 12H3"/>
                              <path d="M11 19H3"/>
                              <path d="m15 18 2 2 4-4"/>
                            </svg>
                            <span class="truncate">{{ event.isFromChecklist ? event.checklistItem?.text || 'Checklist Item' : event.title }}</span>
                          </div>
                        </div>
                      </div>
                    </template>

                    <!-- Regular events for month view -->
                    <template v-else>
                      <div class="day-events-container space-y-1">
                        <div
                          v-for="event in day.events.slice(0, 3)"
                          :key="event.id"
                          class="event-item text-xs p-1 rounded truncate cursor-pointer hover:opacity-90"
                          :style="{
                            backgroundColor: event.isFromChecklist ? '#f1f5f9' : event.stageColor + '40',
                            color: event.isFromChecklist ? '#64748b' : event.stageColor,
                            borderLeft: `2px solid ${event.isFromChecklist ? '#cbd5e1' : event.stageColor}`,
                          }"
                          @click.stop="handleEventClick(event)"
                        >
                          <div class="flex items-center gap-1.5">
                            <svg
                              v-if="event.isFromChecklist"
                              xmlns="http://www.w3.org/2000/svg"
                              width="10"
                              height="10"
                              viewBox="0 0 24 24"
                              fill="none"
                              stroke="currentColor"
                              stroke-width="2.5"
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              class="lucide lucide-list-check-icon lucide-list-check flex-shrink-0 opacity-80"
                            >
                              <path d="M16 5H3"/>
                              <path d="M16 12H3"/>
                              <path d="M11 19H3"/>
                              <path d="m15 18 2 2 4-4"/>
                            </svg>
                            <span class="truncate">{{ event.isFromChecklist ? event.checklistItem?.text || 'Checklist Item' : event.title }}</span>
                          </div>
                        </div>
                        <div
                          v-if="day.events.length > 3"
                          class="text-xs text-slate-500 dark:text-slate-400"
                        >
                          +{{ day.events.length - 3 }} mais
                        </div>
                      </div>
                    </template>
                  </div>
                </div>
              </div>
            </div>
          </div>

        </div>
      </div>

    </div>

    <!-- Substituir o Event Details Modal pelo KanbanItemDetails -->
    <Modal
      v-if="selectedItem && showItemDetails"
      v-model:show="showItemDetails"
      :on-close="handleCloseDetails"
      size="full-width"
    >
      <KanbanItemDetails
        v-if="selectedItem"
        :item-id="selectedItem.id"
        @close="handleCloseDetails"
        @edit="handleItemEdit"
        @item-updated="fetchKanbanItems"
      />
    </Modal>

    <!-- Add Event Modal -->
    <Modal
      v-model:show="showAddModal"
      size="full-width"
      :on-close="() => (showAddModal = false)"
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4">
          {{ t('KANBAN.ADD_ITEM') }}
        </h3>
        <KanbanItemForm
          v-if="store.getters['funnel/getSelectedFunnel']"
          :funnel-id="store.getters['funnel/getSelectedFunnel'].id"
          :initial-date="selectedDate"
          @saved="handleItemCreated"
          @close="showAddModal = false"
        />
      </div>
    </Modal>

    <!-- Adicione o Modal de Edição -->
    <Modal
      v-model:show="showEditModal"
      size="full-width"
      :on-close="() => (showEditModal = false)"
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4">
          {{ t('KANBAN.EDIT_ITEM') }}
        </h3>
        <KanbanItemForm
          v-if="selectedItemToEdit"
          :funnel-id="store.getters['funnel/getSelectedFunnel'].id"
          :stage="selectedItemToEdit.funnel_stage"
          :initial-data="selectedItemToEdit"
          :is-editing="true"
          @saved="handleItemUpdated"
          @close="showEditModal = false"
        />
      </div>
    </Modal>
  </div>
</template>

<style lang="scss" scoped>
.calendar-container {
  @apply bg-white dark:bg-slate-900 h-full flex flex-col;
  position: relative;
  isolation: isolate;
}

.mini-calendar-section {
  @apply relative flex flex-col;
  background-color: inherit;
  height: 100%;
  -ms-overflow-style: none; /* IE and Edge */
  scrollbar-width: none; /* Firefox */

  > div {
    display: flex;
    flex-direction: column;
    -ms-overflow-style: none;
    scrollbar-width: none;

    &::-webkit-scrollbar {
      display: none;
    }
  }

  &::-webkit-scrollbar {
    display: none;
  }
}

.mini-calendar {
  .grid-cols-7 {
    grid-template-columns: repeat(7, minmax(0, 1fr));
  }
  flex-shrink: 0;
}

.calendar-grid {
  @apply grid;
  flex: 1;
  min-height: 0;
  border-left: 1px solid #e2e8f0;
  border-top: 1px solid #e2e8f0;
  position: relative;
  isolation: isolate;
  height: calc(100% - 48px);
  overflow-y: auto;

  &[data-view-mode='week'] {
    grid-template-rows: 1fr;
    display: grid;
    height: 600px; // Ajustado para altura mais razoável sem time slots

    > div {
      flex: 1;
      height: 100%;
      min-height: 600px;
    }

  }

  &[data-view-mode='month'] {
    grid-template-rows: repeat(6, 1fr);
  }
}

.calendar-header {
  @apply sticky top-0;
  background-color: inherit;
}

.week-day-header {
  position: relative;

  &:not(:last-child)::after {
    content: '';
    @apply absolute right-0 top-1/2 -translate-y-1/2 h-4 w-px bg-slate-200 dark:bg-slate-700;
  }
}

.calendar-day {
  @apply p-2 relative;
  height: 100%;
  border-right: 1px solid #e2e8f0;
  border-bottom: 1px solid #e2e8f0;
  border-top: 1px solid #e2e8f0;
  display: flex;
  flex-direction: column;
  isolation: isolate;

  .dark & {
    border-right-color: #334155;
    border-bottom-color: #334155;
    border-top-color: #334155;
  }

  &:hover {
    /* hover styles */
  }

  > div {
    height: 100%;
    display: flex;
    flex-direction: column;
  }

  .day-events-container {
    height: 100%;
    overflow-y: auto;
    overflow-x: hidden;
    -ms-overflow-style: none;
    scrollbar-width: none;

    &::-webkit-scrollbar {
      display: none;
    }
  }

  // Improve spacing for better layout
  .event-item {
    min-height: 24px;
    display: flex;
    align-items: center;
  }

  &[data-view-mode='week'] {
    height: 100%;
    min-height: 100%;
    overflow: hidden;
    border: none; // Remove border from calendar day cells
  }
}

.loading-spinner {
  width: 40px;
  height: 40px;
  border: 3px solid var(--color-border);
  border-top: 3px solid var(--color-woot);
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

// Estilizar a scrollbar horizontal
.overflow-x-auto {
  scrollbar-width: thin;
  scrollbar-color: #94a3b8 transparent;

  &::-webkit-scrollbar {
    height: 6px;
  }

  &::-webkit-scrollbar-track {
    background: transparent;
  }

  &::-webkit-scrollbar-thumb {
    background-color: #94a3b8;
    border-radius: 3px;
  }
}

.dark .overflow-x-auto {
  scrollbar-color: #475569 transparent;

  &::-webkit-scrollbar-thumb {
    background-color: #475569;
  }
}

// Adicionar estilos para a transição
.overflow-hidden {
  overflow: hidden;
}

// Ajustar scrollbar para ser mais sutil
.overflow-x-auto {
  &::-webkit-scrollbar {
    height: 4px;
  }

  &::-webkit-scrollbar-thumb {
    @apply bg-slate-300 dark:bg-slate-600;
    border-radius: 2px;
  }

  &:hover {
    &::-webkit-scrollbar-thumb {
      @apply bg-slate-400 dark:bg-slate-500;
    }
  }
}



// Eventos de hoje
.today-events-section {
  @apply relative;
  padding: 0;
}

.events-list {
  flex: 1;
  min-height: 0;
  -ms-overflow-style: none;
  scrollbar-width: none;

  &::-webkit-scrollbar {
    display: none;
  }
}

// Update flex styles for week view
.calendar-grid {
  &[data-view-mode='week'] {
    border: none; // Remove outer border
    height: 100%;
    overflow: hidden;

    > div {
      border: none; // Remove borders from flex containers
      display: flex;
      width: 100%;
    }
  }
}

// Removido: estilos para time slots

.calendar-day {
  &[data-view-mode='week'] {
    height: 100%;
    min-height: 100%;
    border: none;
    position: relative;
    padding: 8px;
    overflow-y: auto;
    flex: 1;
    min-width: 0; // Allow flex item to shrink below content size
  }
}

</style>
