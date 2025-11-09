<script setup>
import {
  computed,
  ref,
  watch,
  nextTick,
  onMounted,
  onUnmounted,
  inject,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { formatDistanceToNow } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import MarkdownIt from 'markdown-it';
import CustomContextMenu from 'dashboard/components/ui/CustomContextMenu.vue';
import Modal from 'dashboard/components/Modal.vue';
import SendMessageTemplate from './SendMessageTemplate.vue';
import KanbanAPI from '../../../../api/kanban';
import { emitter } from 'shared/helpers/mitt';
import { useConfig } from 'dashboard/composables/useConfig';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import AgentTooltip from './AgentTooltip.vue';
import PriorityCircle from './PriorityCircle.vue';
import { useStore } from 'vuex';
import { onMounted as vueOnMounted } from 'vue';

const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  isDragging: {
    type: Boolean,
    default: false,
  },
  draggable: {
    type: Boolean,
    default: false,
  },
  kanbanItems: {
    type: Array,
    default: () => [],
  },
  forceExpanded: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'click',
  'edit',
  'delete',
  'dragstart',
  'conversationUpdated',
  'itemDragend',
]);

// Injetar o map de labels fornecido pelo componente pai
const labelsMap = inject('labelsMap', {});

const router = useRouter();
const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const { isStacklab } = useConfig();

const store = useStore();

// Instância do MarkdownIt com configurações padrão
const md = new MarkdownIt({
  html: false, // Desabilitar HTML inline para segurança
  breaks: true, // Converter quebras de linha em <br>
  linkify: true, // Converter URLs em links automaticamente
});

// Função para renderizar markdown
const renderMarkdown = text => {
  if (!text) return '';
  return md.render(text);
};

// Computed para obter o usuário atual
const currentUser = computed(() => store.getters.getCurrentUser);

// Watch para mudanças no item (para garantir reatividade)
watch(
  () => props.item,
  (newItem, oldItem) => {
    if (newItem && oldItem && newItem.id === oldItem.id) {
      // Item foi atualizado, forçar reatividade se necessário
      if (
        JSON.stringify(newItem.item_details) !==
        JSON.stringify(oldItem.item_details)
      ) {
        // O Vue deve detectar as mudanças automaticamente devido aos computed properties
      }
    }
  },
  { deep: true }
);

// Computed para verificar se o item é visível para o usuário atual
const isItemVisible = computed(() => {
  // Se não há usuário atual, não mostrar o item
  if (!currentUser.value) return false;

  // Se o usuário é administrador, sempre mostrar
  if (currentUser.value.role === 'administrator') return true;

  // Se não há agentes atribuídos, apenas administradores podem ver
  if (!props.item.assigned_agents || props.item.assigned_agents.length === 0)
    return false;

  // Verificar se o usuário atual está na lista de agentes atribuídos
  return props.item.assigned_agents.some(
    agent => agent.id === currentUser.value.id
  );
});

// Ref para armazenar os dados da conversa - agora busca pelo display_id
const conversationData = computed(() => {
  // Se existir conversation_display_id e kanbanItems, buscar a conversa correspondente
  if (props.item.conversation_display_id && Array.isArray(props.kanbanItems)) {
    // Procura o item que tenha conversation.display_id igual ao informado
    const found = props.kanbanItems.find(
      kItem =>
        kItem.conversation &&
        String(kItem.conversation.display_id) ===
          String(props.item.conversation_display_id)
    );
    if (found && found.conversation) {
      return found.conversation;
    }
  }
  // Fallback: usa a conversa do próprio item
  return props.item.conversation || null;
});

const priorityInfo = computed(() => {
  // Buscar prioridade do item_details
  const priority = props.item.item_details?.priority?.toLowerCase() || 'none';

  // Se for none, retorna null para não exibir o badge
  if (priority === 'none') return null;

  const priorityMap = {
    high: {
      label: t('KANBAN.PRIORITY_LABELS.HIGH'),
      class: 'bg-ruby-50 dark:bg-ruby-800 text-ruby-800 dark:text-ruby-50',
    },
    medium: {
      label: t('KANBAN.PRIORITY_LABELS.MEDIUM'),
      class:
        'bg-yellow-50 dark:bg-yellow-800 text-yellow-800 dark:text-yellow-50',
    },
    low: {
      label: t('KANBAN.PRIORITY_LABELS.LOW'),
      class: 'bg-green-50 dark:bg-green-800 text-green-800 dark:text-green-50',
    },
    urgent: {
      label: t('KANBAN.PRIORITY_LABELS.URGENT'),
      class: 'bg-red-50 dark:bg-red-800 text-red-800 dark:text-red-50',
    },
  };

  return priorityMap[priority] || null;
});

const formattedDate = computed(() => {
  const dateStr = props.item.created_at || props.item.createdAt;
  if (!dateStr) return '';

  try {
    const date = new Date(dateStr);
    return t('KANBAN.CREATED_AT_FORMAT', {
      date: new Intl.DateTimeFormat('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      }).format(date),
    });
  } catch (error) {
    return '';
  }
});

const formattedValue = computed(() => {
  const value = props.item.item_details?.value;
  const currency = props.item.item_details?.currency;

  if (!value && value !== 0) return null;

  try {
    return new Intl.NumberFormat(currency?.locale || 'pt-BR', {
      style: 'currency',
      currency: currency?.code || 'BRL',
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(value);
  } catch (error) {
    return value.toString();
  }
});

const formattedDeadline = computed(() => {
  const deadline = props.item.item_details?.deadline_at;
  const scheduled = props.item.item_details?.scheduled_at;
  const schedulingType = props.item.item_details?.scheduling_type;

  if (!deadline && !scheduled) return null;

  try {
    const dateStr = scheduled || deadline;

    // Ajuste para corrigir o problema da data
    // Adicione a hora como T12:00:00 para evitar problemas de fuso horário
    let adjustedDateStr = dateStr;
    if (dateStr && dateStr.length === 10) {
      adjustedDateStr = `${dateStr}T12:00:00`;
    }

    const date = new Date(adjustedDateStr);

    if (!Number.isFinite(date.getTime())) {
      return null;
    }

    // Formatação personalizada sem ano
    const day = date.getDate().toString().padStart(2, '0');
    const month = (date.getMonth() + 1).toString().padStart(2, '0');

    let formattedDate = `${day}/${month}`;

    // Adiciona horário se for agendamento
    if (schedulingType === 'schedule' && scheduled) {
      const hours = date.getHours().toString().padStart(2, '0');
      const minutes = date.getMinutes().toString().padStart(2, '0');
      formattedDate += ` ${hours}:${minutes}`;
    }

    return formattedDate;
  } catch (error) {
    return null;
  }
});

const scheduleIcon = computed(() => {
  const schedulingType = props.item.item_details?.scheduling_type;
  if (!schedulingType) return 'alarm';
  return schedulingType === 'schedule' ? 'calendar' : 'alarm';
});

const truncatedTitle = computed(() => {
  const titleValue = props.item.item_details?.title || '';
  if (titleValue.length > 15) {
    return `${titleValue.substring(0, 15)}...`;
  }
  return titleValue;
});

const truncatedSenderName = computed(() => {
  const name = conversationData.value?.contact?.name;
  const email = conversationData.value?.contact?.email;
  const defaultText = t('ITEM_CONVERSATION.NO_CONTACT');
  const text = name || email || defaultText;

  return text.length > 25 ? `${text.substring(0, 25)}...` : text;
});

const truncatedLastMessage = computed(() => {
  const message = conversationData.value?.last_message?.content;
  if (!message) return '';

  // Remove quebras de linha e espaços extras
  const cleanMessage = message.replace(/\s+/g, ' ').trim();

  return cleanMessage.length > 30
    ? `${cleanMessage.substring(0, 30)}...`
    : cleanMessage;
});

const handleClick = () => {
  // Navegar para a rota kanban_board com o parâmetro item, igual aos itens recentes da sidebar
  router.push(accountScopedRoute('kanban_board', {}, { item: props.item.id }));
  emit('click', props.item);
};

const handleEdit = e => {
  e.stopPropagation();
  emit('edit', props.item);
};

// Adicionar ref para controlar o modal
const showDeleteModal = ref(false);
const itemToDelete = ref(null);

// Modificar o método de delete para mostrar o modal primeiro
const handleDelete = e => {
  e.stopPropagation();
  itemToDelete.value = props.item;
  showDeleteModal.value = true;
};

// Adicionar método para confirmar a exclusão
const confirmDelete = () => {
  emit('delete', itemToDelete.value);
  showDeleteModal.value = false;
  itemToDelete.value = null;
};

// Função para navegar para a conversa
const navigateToConversation = (e, conversationDisplayId) => {
  e.stopPropagation(); // Previne a propagação do clique para o card

  if (!conversationDisplayId || !conversationData.value) return;

  const route = router.resolve({
    name: 'inbox_conversation',
    params: {
      accountId: props.item.account_id,
      inboxId: conversationData.value.inbox_id,
      conversation_id: conversationDisplayId,
    },
  });
  window.open(route.href, '_blank');
};

// Adicione essas novas refs e funções
const showContextMenu = ref(false);
const contextMenuPosition = ref({ x: 0, y: 0 });

const handleContextMenu = e => {
  const conversation = props.item.conversation;
  const conversationId =
    conversation?.id || props.item.item_details?.conversation_id;
  if (!conversation || !conversationId) return;

  e.preventDefault();
  showContextMenu.value = true;
  contextMenuPosition.value = {
    x: e.clientX,
    y: e.clientY,
  };
};

const showSendMessageModal = ref(false);

const handleQuickMessage = () => {
  try {
    nextTick(() => {
      showContextMenu.value = false;
      showSendMessageModal.value = true;
    });
  } catch (error) {
    // Handle error silently
  }
};

const handleViewContact = () => {
  // Fecha o menu de contexto
  showContextMenu.value = false;

  // Verifica se temos os dados necessários
  if (!conversationData.value?.contact?.id) {
    return;
  }

  try {
    // Navega para a página do contato
    router.push({
      name: 'contact_profile',
      params: {
        accountId: conversationData.value.account_id,
        contactId: conversationData.value.contact.id,
      },
      query: {
        page: 1,
      },
    });
  } catch (err) {
    // Fallback: navegação direta pela URL
    window.location.href = `/app/accounts/${conversationData.value.account_id}/contacts/${conversationData.value.contact.id}?page=1`;
  }
};

const handleDragStart = e => {
  emit('dragstart', e);
};

// Add new handler for dragend
const handleDragEnd = e => {
  emit('itemDragend', e);
};

// Adicionar watch para monitorar mudanças
watch(showSendMessageModal, newValue => {
  if (!newValue) {
    nextTick(() => {
      showContextMenu.value = false;
    });
  }
});

// Adicione essa nova ref
const showFullDescription = ref(false);

// Corrigido: só retorna a descrição se existir
const truncatedDescription = computed(() => {
  const description = props.item.item_details?.description;
  if (!description) return '';
  if (showFullDescription.value) return description;

  // Renderizar markdown primeiro, depois truncar o HTML
  const rendered = renderMarkdown(description);
  if (rendered.length <= 150) return rendered;

  // Truncar o HTML mantendo as tags válidas
  const truncated = rendered.substring(0, 150);
  const lastTagStart = truncated.lastIndexOf('<');
  const lastTagEnd = truncated.lastIndexOf('>');

  // Se há uma tag aberta no final, fechar ela
  if (lastTagStart > lastTagEnd) {
    return truncated.substring(0, lastTagStart) + '...';
  }

  return truncated + '...';
});

// Adicione essa nova função
const toggleDescription = e => {
  e.stopPropagation();
  showFullDescription.value = !showFullDescription.value;
};

const handleFilter = filters => {
  const filteredItems = props.kanbanItems.filter(item => {
    // Lógica de filtro aqui
  });
  emit('filter', filteredItems);
};

// Computed agentInfo para trabalhar com múltiplos agentes
const agentInfo = computed(() => {
  // Verificar se há agentes atribuídos
  if (props.item.assigned_agents && props.item.assigned_agents.length > 0) {
    return props.item.assigned_agents.map(agent => ({
      id: agent.id,
      name: agent.name,
      avatar_url: agent.avatar_url || '',
      assigned_at: agent.assigned_at,
      assigned_by: agent.assigned_by,
    }));
  }

  return [];
});

// Computed para o agente principal (primeiro da lista)
const primaryAgent = computed(() => {
  return agentInfo.value.length > 0 ? agentInfo.value[0] : null;
});

// Computed para mostrar se há múltiplos agentes
const hasMultipleAgents = computed(() => {
  return agentInfo.value.length > 1;
});

// Computed para mostrar o número de agentes adicionais
const additionalAgentsCount = computed(() => {
  return Math.max(0, agentInfo.value.length - 1);
});

// Adicionar nova ref para controlar o menu de opções
const showOptionsMenu = ref(false);

// Fechar menu ao clicar fora
onMounted(() => {
  document.addEventListener('click', () => {
    showOptionsMenu.value = false;
  });

  // Carregar configurações de visibilidade
  const allSettings = JSON.parse(
    localStorage.getItem('kanban_items_visibility') || '{}'
  );
  const itemSettings = allSettings[props.item.id];

  if (itemSettings) {
    try {
      showDescriptionField.value = itemSettings.showDescriptionField ?? true;
      showLabelsField.value = itemSettings.showLabelsField ?? true;
      showPriorityField.value = itemSettings.showPriorityField ?? true;
      showValueField.value = itemSettings.showValueField ?? true;
      showDeadlineField.value = itemSettings.showDeadlineField ?? true;
      showConversationField.value = itemSettings.showConversationField ?? true;
      showChecklistField.value = itemSettings.showChecklistField ?? true;
      showAgentField.value = itemSettings.showAgentField ?? true;
      showMetadataField.value = itemSettings.showMetadataField ?? true;
    } catch (error) {
      // Handle error silently
    }
  }

  // Carregar estado de colapso
  loadCollapsedState();

  // Adicionar listener para evento global
  emitter.on('kanbanItemsCollapsedStateChanged', loadCollapsedState);

  if (!agentList.value.length) {
    store.dispatch('agents/get');
  }
});

onUnmounted(() => {
  document.removeEventListener('click', () => {
    showOptionsMenu.value = false;
  });

  // Remover o listener ao desmontar o componente
  emitter.off('kanbanItemsCollapsedStateChanged', loadCollapsedState);
});

// Função para carregar o estado de colapso do localStorage
const loadCollapsedState = () => {
  const collapsedItems = JSON.parse(
    localStorage.getItem('kanban_collapsed_items') || '{}'
  );

  if (props.item.id in collapsedItems) {
    isItemCollapsed.value = collapsedItems[props.item.id];
  }
};

const showStatusModal = ref(false);
const statusForm = ref({
  status: '',
  reason: '',
  selectedOffer: null,
  selectedWinReason: null,
  selectedLossReason: null,
});

// Computed para buscar funnels ativos
const funnels = computed(() =>
  store.getters['funnel/getFunnels'].filter(funnel => funnel.active)
);

// Computed para buscar o funil atual do item
const currentFunnel = computed(() => {
  // Tentar diferentes formas de buscar o funnel_id
  const funnelId = props.item.funnel_id || props.item.funnel?.id;

  if (!funnelId) return null;

  // Usar == para comparar número com string
  return funnels.value.find(f => f.id == funnelId);
});

// Computed para motivos de ganho
const winReasons = computed(() => {
  return currentFunnel.value?.settings?.win_reasons || [];
});

// Computed para motivos de perda
const lossReasons = computed(() => {
  return currentFunnel.value?.settings?.loss_reasons || [];
});

const handleStatusClick = async () => {
  // Buscar funnels antes de abrir o modal
  try {
    await store.dispatch('funnel/fetch');
  } catch (error) {
    console.error('Erro ao buscar funnels:', error);
  }

  // Inicializa o form com o status atual
  // Se não há status no item_details, usar o status da conversa como fallback
  const currentStatus =
    props.item.item_details?.status || conversationData.value?.status || 'open';

  statusForm.value = {
    status: currentStatus,
    reason: props.item.item_details?.reason || '',
    selectedOffer: props.item.item_details?.closed_offer || null,
    selectedWinReason: props.item.item_details?.win_reason || null,
    selectedLossReason: props.item.item_details?.loss_reason || null,
  };

  showStatusModal.value = true;
};

const handleStatusSave = async () => {
  try {
    // Preparar o campo reason baseado no status
    let reasonText = null;

    if (statusForm.value.status === 'won') {
      // Se selecionou "Outro", usar o texto do textarea
      if (statusForm.value.selectedWinReason === 'other') {
        reasonText = statusForm.value.reason || null;
      } else {
        // Usar o título do win_reason selecionado
        const selectedReason = winReasons.value.find(
          r => r.id === statusForm.value.selectedWinReason
        );
        reasonText = selectedReason?.title || null;
      }
    } else if (statusForm.value.status === 'lost') {
      // Se selecionou "Outro", usar o texto do textarea
      if (statusForm.value.selectedLossReason === 'other') {
        reasonText = statusForm.value.reason || null;
      } else {
        // Usar o título do loss_reason selecionado
        const selectedReason = lossReasons.value.find(
          r => r.id === statusForm.value.selectedLossReason
        );
        reasonText = selectedReason?.title || null;
      }
    }

    // Sempre fazer update completo do item_details para garantir que o status seja atualizado
    const updatedItem = {
      ...props.item,
      item_details: {
        ...props.item.item_details,
        status: statusForm.value.status,
        reason: reasonText,
        closed_offer:
          statusForm.value.status === 'won'
            ? statusForm.value.selectedOffer
            : null,
        win_reason:
          statusForm.value.status === 'won' &&
          statusForm.value.selectedWinReason !== 'other'
            ? statusForm.value.selectedWinReason
            : null,
        loss_reason:
          statusForm.value.status === 'lost' &&
          statusForm.value.selectedLossReason !== 'other'
            ? statusForm.value.selectedLossReason
            : null,
      },
    };

    const { data } = await KanbanAPI.update(props.item.id, updatedItem);
    if (data) {
      Object.assign(props.item, data);
    }

    showStatusModal.value = false;
    emit('conversationUpdated');

    // Mostrar toast de sucesso
    emitter.emit('newToastMessage', {
      message: 'Status atualizado com sucesso',
      type: 'success',
    });
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: 'Erro ao atualizar status',
      type: 'error',
    });
  }
};

// Adicione este computed
const getStatusLabel = computed(() => {
  const status = props.item.item_details?.status;

  if (!status) return t('KANBAN.BULK_ACTIONS.ITEM_STATUS.OPEN');

  if (status === 'won') {
    const date = new Date(
      props.item.item_details?.updated_at
    ).toLocaleDateString();
    return t('KANBAN.BULK_ACTIONS.ITEM_STATUS.WON');
  }

  if (status === 'lost') {
    const date = new Date(
      props.item.item_details?.updated_at
    ).toLocaleDateString();
    return t('KANBAN.BULK_ACTIONS.ITEM_STATUS.LOST');
  }

  return 'Status';
});

// Adicione este computed para exibir o status real do item (badge do card)
const displayedStatus = computed(() => {
  // Sempre pega do item_details.status, se não tiver marca como 'open'
  const itemStatus = props.item.item_details?.status || 'open';

  if (itemStatus === 'open') {
    return t('KANBAN.BULK_ACTIONS.ITEM_STATUS.OPEN');
  }
  if (itemStatus === 'won') {
    return t('KANBAN.BULK_ACTIONS.ITEM_STATUS.WON');
  }
  if (itemStatus === 'lost') {
    return t('KANBAN.BULK_ACTIONS.ITEM_STATUS.LOST');
  }
  if (itemStatus === 'pending') {
    return t('KANBAN.ITEM_STATUS.PENDING');
  }
  if (itemStatus === 'resolved') {
    return t('KANBAN.ITEM_STATUS.RESOLVED');
  }
  if (itemStatus === 'snoozed') {
    return t('KANBAN.ITEM_STATUS.SNOOZED');
  }
  return itemStatus;
});

// Atualizado para usar o novo formato do backend (total_count)
const attachmentsCount = computed(() => {
  // Verifica se attachments é um array (formato show) ou objeto com total_count (formato index)
  if (Array.isArray(props.item.attachments)) {
    // Formato antigo/completo: soma todos os anexos
    const itemAttachments = props.item.attachments?.length || 0;
    const itemDetailsAttachments =
      props.item.item_details?.attachments?.length || 0;
    const noteAttachments = Array.isArray(props.item.item_details?.notes)
      ? props.item.item_details.notes.reduce((count, note) => {
          return count + (note.attachments?.length || 0);
        }, 0)
      : 0;

    return itemAttachments + itemDetailsAttachments + noteAttachments;
  }
  // Novo formato do index: usa total_count diretamente
  return props.item.attachments?.total_count || 0;
});

// Atualizado para usar o novo formato do backend (total_count)
const notesCount = computed(() => {
  const notes = props.item.item_details?.notes;

  // Verifica se notes é um array (formato show) ou objeto com total_count (formato index)
  if (Array.isArray(notes)) {
    // Formato antigo/completo: conta os itens do array
    return notes?.length || 0;
  }
  // Novo formato do index: usa total_count diretamente
  return notes?.total_count || 0;
});

// Adiciona computed properties para o progresso do checklist
// Atualizado para usar o novo formato do backend (total_count e completed_count)
const totalItems = computed(() => {
  // Verifica se checklist é um array (formato show) ou objeto com contagens (formato index)
  if (Array.isArray(props.item.checklist)) {
    // Formato antigo/completo: conta os itens do array
    return props.item.checklist?.length || 0;
  }
  // Novo formato do index: usa total_count diretamente
  return props.item.checklist?.total_count || 0;
});

const completedItems = computed(() => {
  // Verifica se checklist é um array (formato show) ou objeto com contagens (formato index)
  if (Array.isArray(props.item.checklist)) {
    // Formato antigo/completo: conta os itens completados
    return props.item.checklist?.filter(item => item.completed)?.length || 0;
  }
  // Novo formato do index: usa completed_count diretamente
  return props.item.checklist?.completed_count || 0;
});

const checklistProgress = computed(() => {
  if (totalItems.value === 0) return 0;
  return (completedItems.value / totalItems.value) * 100;
});

// Adicione uma computed property para o tempo na etapa
const timeInStage = computed(() => {
  if (!props.item.stage_entered_at) return '';
  try {
    const now = new Date();
    const entered = new Date(props.item.stage_entered_at);
    const diffMs = now - entered;
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);
    const diffYears = Math.floor(diffDays / 365);
    if (diffYears > 0) return `${diffYears}a`;
    if (diffDays > 0) return `${diffDays}d`;
    if (diffHours > 0) return `${diffHours}h`;
    if (diffMins > 0) return `${diffMins}m`;
    return '<1m';
  } catch (error) {
    return '';
  }
});

// Adicione este computed
const conversationLabels = computed(() => {
  return conversationData.value?.label_list || [];
});

// Adicione esta função helper para escurecer cores
const darkenColor = (color, amount = 0.2) => {
  try {
    if (!color) return '#64748B';

    // Remove o # se existir
    const hex = color.replace('#', '');

    // Converte para RGB
    const r = parseInt(hex.substring(0, 2), 16);
    const g = parseInt(hex.substring(2, 4), 16);
    const b = parseInt(hex.substring(4, 6), 16);

    // Escurece cada componente
    const darkerR = Math.floor(r * (1 - amount));
    const darkerG = Math.floor(g * (1 - amount));
    const darkerB = Math.floor(b * (1 - amount));

    // Converte de volta para hex
    return `#${darkerR.toString(16).padStart(2, '0')}${darkerG
      .toString(16)
      .padStart(2, '0')}${darkerB.toString(16).padStart(2, '0')}`;
  } catch {
    return '#64748B';
  }
};

// Adicione este computed
const contactAvatar = computed(() => {
  return conversationData.value?.contact?.thumbnail || '';
});

// Computed para obter as offers disponíveis do item
const availableOffers = computed(() => {
  const offers = props.item.item_details?.offers || [];
  return Array.isArray(offers) ? offers : [];
});

// Método para obter o estilo do badge de status do item
const getStatusBadgeStyle = () => {
  // Sempre pega do item_details.status, se não tiver marca como 'open'
  const effectiveStatus = props.item.item_details?.status || 'open';

  switch (effectiveStatus) {
    case 'won':
      return {
        backgroundColor: '#dcfce7',
        color: '#166534',
        border: '1px solid #bbf7d0',
      };
    case 'lost':
      return {
        backgroundColor: '#fee2e2',
        color: '#991b1b',
        border: '1px solid #fecaca',
      };
    case 'open':
      return {
        backgroundColor: '#f1f5f9',
        color: '#334155',
        border: '1px solid #e2e8f0',
      };
    case 'pending':
      return {
        backgroundColor: '#fef9c3',
        color: '#b45309',
        border: '1px solid #fde68a',
      };
    case 'resolved':
      return {
        backgroundColor: '#dbeafe',
        color: '#1e40af',
        border: '1px solid #bfdbfe',
      };
    case 'snoozed':
      return {
        backgroundColor: '#f3f4f6',
        color: '#374151',
        border: '1px solid #d1d5db',
      };
    default:
      return {
        backgroundColor: '#f1f5f9',
        color: '#334155',
        border: '1px solid #e2e8f0',
      };
  }
};

// Computed para cor de fundo do badge de status da conversa vinculada
const conversationStatusBadgeStyle = computed(() => {
  const status = conversationData.value?.status;
  // Paleta sutil, tons pastel e elegantes
  switch (status) {
    case 'open':
      return {
        background: 'linear-gradient(90deg, #e0f2fe 0%, #bae6fd 100%)',
        color: '#0369a1',
        border: '1px solid #bae6fd',
      };
    case 'pending':
      return {
        background: 'linear-gradient(90deg, #fef9c3 0%, #fde68a 100%)',
        color: '#b45309',
        border: '1px solid #fde68a',
      };
    case 'resolved':
      return {
        background: 'linear-gradient(90deg, #dcfce7 0%, #bbf7d0 100%)',
        color: '#166534',
        border: '1px solid #bbf7d0',
      };
    case 'snoozed':
      return {
        background: 'linear-gradient(90deg, #f3f4f6 0%, #e5e7eb 100%)',
        color: '#334155',
        border: '1px solid #e5e7eb',
      };
    case 'lost':
      return {
        background: 'linear-gradient(90deg, #fee2e2 0%, #fecaca 100%)',
        color: '#991b1b',
        border: '1px solid #fecaca',
      };
    case 'won':
      return {
        background: 'linear-gradient(90deg, #f0fdf4 0%, #bbf7d0 100%)',
        color: '#166534',
        border: '1px solid #bbf7d0',
      };
    default:
      return {
        background: 'linear-gradient(90deg, #f1f5f9 0%, #e2e8f0 100%)',
        color: '#334155',
        border: '1px solid #e2e8f0',
      };
  }
});

// Adicione estas refs para controlar a visibilidade dos campos
const showDescriptionField = ref(true);
const showLabelsField = ref(true);
const showPriorityField = ref(true);
const showValueField = ref(true);
const showDeadlineField = ref(true);
const showConversationField = ref(true);
const showChecklistField = ref(true);
const showAgentField = ref(true);
const showMetadataField = ref(true);

// Adicionar ref para controlar o estado expandido/colapsado
const isItemCollapsed = ref(false);

// Adicione este ref e função para controlar o modal de visibilidade
const showVisibilityModal = ref(false);

const handleVisibilityClick = () => {
  showOptionsMenu.value = false;
  showVisibilityModal.value = true;
};

// Função para alternar entre expandido/colapsado
const toggleCollapseItem = () => {
  isItemCollapsed.value = !isItemCollapsed.value;
  saveItemCollapsedState();
  showOptionsMenu.value = false;
};

// Função para salvar o estado de colapso no localStorage
const saveItemCollapsedState = () => {
  const collapsedItems = JSON.parse(
    localStorage.getItem('kanban_collapsed_items') || '{}'
  );
  collapsedItems[props.item.id] = isItemCollapsed.value;
  localStorage.setItem(
    'kanban_collapsed_items',
    JSON.stringify(collapsedItems)
  );
};

// Função para salvar configurações no localStorage
const saveFieldVisibility = () => {
  const settings = {
    showDescriptionField: showDescriptionField.value,
    showLabelsField: showLabelsField.value,
    showPriorityField: showPriorityField.value,
    showValueField: showValueField.value,
    showDeadlineField: showDeadlineField.value,
    showConversationField: showConversationField.value,
    showChecklistField: showChecklistField.value,
    showAgentField: showAgentField.value,
    showMetadataField: showMetadataField.value,
  };

  // Carregar configurações existentes
  const allSettings = JSON.parse(
    localStorage.getItem('kanban_items_visibility') || '{}'
  );

  // Atualizar apenas as configurações deste item específico
  allSettings[props.item.id] = settings;

  // Salvar de volta no localStorage
  localStorage.setItem('kanban_items_visibility', JSON.stringify(allSettings));
};

// Observe as mudanças em todas as configurações de visibilidade
watch(
  [
    showDescriptionField,
    showLabelsField,
    showPriorityField,
    showValueField,
    showDeadlineField,
    showConversationField,
    showChecklistField,
    showAgentField,
    showMetadataField,
  ],
  () => {
    saveFieldVisibility();
  }
);

const isUrgent = computed(
  () => props.item.item_details?.priority?.toLowerCase() === 'urgent'
);

// Atualizar isItemCollapsed para respeitar forceExpanded
watch(
  () => props.forceExpanded,
  newVal => {
    if (newVal) {
      isItemCollapsed.value = false;
    }
  },
  { immediate: true }
);

// Modal de atribuição rápida de agente
const showAgentAssignModal = ref(false);
const agentAssignLoading = ref(false);
const selectedAgentId = ref(null);
const agentList = computed(() => store.getters['agents/getAgents']);

// Hover state para avatar do agente
const showEditAgentIcon = ref(false);

// Função segura para ícone
function safeIcon(icon) {
  if (typeof icon === 'string' && icon.length > 0) return icon;
  return 'user';
}

// Função para abrir modal
const openAgentAssignModal = () => {
  console.log('[KanbanItem] Opening agent assign modal:', {
    agentInfo: agentInfo.value,
    primaryAgent: primaryAgent.value,
    primaryAgentId: primaryAgent.value?.id,
    item: props.item,
    assigned_agents: props.item?.assigned_agents,
  });

  selectedAgentId.value = primaryAgent.value?.id || null;
  console.log('[KanbanItem] Set selectedAgentId to:', selectedAgentId.value);

  showAgentAssignModal.value = true;
};

// Função para atribuir agente (atualizada para múltiplos)
const assignAgent = async () => {
  if (!selectedAgentId.value || agentAssignLoading.value) return;
  agentAssignLoading.value = true;
  try {
    // Usar o novo endpoint para atribuir agente
    const { data } = await KanbanAPI.assignAgent(
      props.item.id,
      selectedAgentId.value
    );
    if (data) {
      Object.assign(props.item, data);
    }
    showAgentAssignModal.value = false;
    emit('conversationUpdated');
    emitter.emit('newToastMessage', {
      message: t('KANBAN.FORM.AGENT.ASSIGNED_SUCCESS'),
      type: 'success',
    });
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: t('KANBAN.FORM.AGENT.ASSIGNED_ERROR'),
      type: 'error',
    });
  } finally {
    agentAssignLoading.value = false;
  }
};

// Função para remover agente
const removeAgent = async agentId => {
  try {
    const { data } = await KanbanAPI.removeAgent(props.item.id, agentId);
    if (data) {
      Object.assign(props.item, data);
    }
    emit('conversationUpdated');
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

// Garantir que a lista de agentes está carregada
vueOnMounted(() => {
  if (!agentList.value.length) {
    store.dispatch('agents/get');
  }
});

// Ref para busca de agente
const agentSearch = ref('');
const filteredAgentList = computed(() => {
  if (!agentSearch.value) return agentList.value;
  return agentList.value.filter(agent =>
    (agent.name || '').toLowerCase().includes(agentSearch.value.toLowerCase())
  );
});

const isConversationCardHovered = ref(false);

// Ref para controlar o modal de prioridade
const showPriorityModal = ref(false);
const priorityAssignLoading = ref(false);
const selectedPriority = ref(props.item.item_details?.priority || 'none');

const openPriorityModal = () => {
  selectedPriority.value = props.item.item_details?.priority || 'none';
  showPriorityModal.value = true;
};

const assignPriority = async () => {
  if (priorityAssignLoading.value) return;
  priorityAssignLoading.value = true;
  try {
    const updatedItem = {
      ...props.item,
      item_details: {
        ...props.item.item_details,
        priority: selectedPriority.value,
      },
    };
    const { data } = await KanbanAPI.update(props.item.id, updatedItem);
    if (data) {
      Object.assign(props.item, data);
    }
    showPriorityModal.value = false;
    emit('conversationUpdated');
    emitter.emit('newToastMessage', {
      message: t('KANBAN.FORM.PRIORITY.ASSIGNED_SUCCESS'),
      type: 'success',
    });
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: t('KANBAN.FORM.PRIORITY.ASSIGNED_ERROR'),
      type: 'error',
    });
  } finally {
    priorityAssignLoading.value = false;
  }
};
</script>

<template>
  <div
    v-if="isItemVisible"
    class="flex flex-col p-4 bg-white dark:bg-slate-900 rounded-lg border border-slate-100 dark:border-slate-800 shadow-sm hover:shadow-md transition-all duration-200 cursor-pointer mt-3 hover:scale-[1.02] hover:-translate-y-0.5"
    :class="{ 'opacity-50': isDragging }"
    :style="isUrgent ? 'border: 1px dashed #DC2626;' : ''"
    :draggable="draggable"
    @dragstart="handleDragStart"
    @dragend="handleDragEnd"
    @click="handleClick"
  >
    <div class="flex items-center justify-between mb-3">
      <div class="flex items-center gap-2">
        <!-- Avatar do contato -->
        <Avatar
          v-if="contactAvatar"
          :src="contactAvatar"
          :name="truncatedTitle"
          :size="24"
        />

        <div class="flex items-center gap-2">
          <h3
            class="text-[13px] font-medium text-slate-900 dark:text-slate-100"
          >
            {{ truncatedTitle }}
          </h3>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <div class="flex items-center gap-2">
          <!-- Tempo na etapa -->
          <div v-if="timeInStage" class="flex items-center gap-1">
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
              class="text-slate-500 dark:text-slate-400 flex-shrink-0"
            >
              <path d="M12 6v6l4 2" />
              <circle cx="12" cy="12" r="10" />
            </svg>
            <span class="text-[11px] font-medium text-slate-500">
              {{ timeInStage }}
            </span>
          </div>

          <!-- Status Badge -->
          <button
            class="px-2 py-1 text-xs font-medium rounded-full flex items-center gap-1 transition-colors"
            :style="getStatusBadgeStyle()"
            @click.stop="handleStatusClick"
          >
            <svg
              v-if="
                props.item.item_details?.status === 'won' ||
                props.item.item_details?.status === 'lost' ||
                conversationData?.status === 'resolved'
              "
              xmlns="http://www.w3.org/2000/svg"
              width="12"
              height="12"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="w-3 h-3"
            >
              <polyline points="20 6 9 17 4 12" />
            </svg>
            <span>
              {{ displayedStatus }}
            </span>
            <PriorityCircle
              v-if="
                showPriorityField &&
                props.item.item_details?.priority &&
                props.item.item_details.priority !== 'none'
              "
              :priority="props.item.item_details.priority"
              :size="14"
              class="ml-1"
            />
          </button>

          <!-- More Options Button -->
          <div class="relative">
            <fluent-icon
              icon="more-vertical"
              size="16"
              class="text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-100 transition-colors cursor-pointer"
              @click.stop="showOptionsMenu = !showOptionsMenu"
            />

            <!-- Menu de Opções -->
            <div
              v-if="showOptionsMenu"
              class="absolute right-0 top-full mt-1 bg-white dark:bg-slate-900 rounded-md shadow-lg border border-slate-100 dark:border-slate-800 w-[170px] min-w-[140px] flex flex-col gap-1 z-10"
              style="box-shadow: 0 4px 24px 0 rgba(30, 41, 59, 0.08)"
              @click.stop
            >
              <button
                class="w-full px-3 py-1.5 text-left text-xs font-normal hover:bg-slate-50 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-200 rounded-none transition-colors"
                @click.stop="handleEdit($event)"
              >
                <span class="flex items-center gap-2">
                  <fluent-icon icon="edit" size="16" />
                  {{ t('KANBAN.ACTIONS.EDIT') }}
                </span>
              </button>
              <button
                v-if="isStacklab === true"
                class="w-full px-3 py-1.5 text-left text-xs font-normal hover:bg-slate-50 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-200 rounded-none transition-colors"
                @click.stop="handleVisibilityClick"
              >
                <span class="flex items-center gap-2">
                  <fluent-icon icon="eye-show" size="16" />
                  {{ t('KANBAN.CONTEXT_MENU.CUSTOMIZE_FIELDS.TITLE') }}
                </span>
              </button>
              <button
                class="w-full px-3 py-1.5 text-left text-xs font-normal hover:bg-slate-50 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-200 rounded-none transition-colors"
                @click.stop="toggleCollapseItem"
              >
                <span class="flex items-center gap-2">
                  <fluent-icon
                    :icon="isItemCollapsed ? 'arrow-expand' : 'arrow-outwards'"
                    size="16"
                  />
                  {{
                    isItemCollapsed
                      ? t('KANBAN.CONTEXT_MENU.EXPAND')
                      : t('KANBAN.CONTEXT_MENU.COLLAPSE')
                  }}
                </span>
              </button>
              <button
                class="w-full px-3 py-1.5 text-left text-xs font-normal hover:bg-slate-50 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-200 rounded-none transition-colors"
                @click.stop="handleDelete($event)"
              >
                <span class="flex items-center gap-2">
                  <fluent-icon icon="delete" size="16" />
                  {{ t('KANBAN.ACTIONS.DELETE') }}
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div
      v-if="showDescriptionField && props.item.item_details?.description"
      class="text-[11px] text-slate-600 dark:text-slate-400 mb-3"
    >
      <div
        class="prose prose-sm max-w-none dark:prose-invert"
        v-html="truncatedDescription"
      />
      <span
        v-if="
          !showFullDescription &&
          renderMarkdown(props.item.item_details.description).length > 150
        "
        class="text-[10px] font-medium text-woot-500 dark:text-woot-400 hover:underline cursor-pointer inline-block mt-1"
        @click="toggleDescription"
      >
        {{
          showFullDescription ? t('KANBAN.READ_LESS') : t('KANBAN.READ_MORE')
        }}
      </span>
    </div>

    <!-- Informação da Conversa -->
    <AgentTooltip text="Clique com o botão direito para ver mais opções.">
      <div
        v-if="
          showConversationField &&
          !isItemCollapsed &&
          item.item_details?.conversation_id &&
          conversationData
        "
        class="flex items-center gap-2 mb-3 px-3.5 py-1.5 bg-white dark:bg-slate-900 rounded-md shadow-lg border border-slate-100 dark:border-slate-800 min-h-[1.5rem] cursor-pointer transition-colors text-xs conversation-card-gradient"
        :style="{
          boxShadow: '0 4px 24px 0 rgba(30,41,59,0.08)',
          background: isConversationCardHovered
            ? `linear-gradient(90deg, ${
                conversationStatusBadgeStyle.background?.split(' ')[0] ||
                '#e0f2fe'
              }22 0%, transparent 100%)`
            : '',
        }"
        @mouseenter="isConversationCardHovered = true"
        @mouseleave="isConversationCardHovered = false"
        @click="navigateToConversation($event, item.conversation?.display_id)"
        @contextmenu="handleContextMenu"
      >
        <span
          class="text-xs text-slate-500 dark:text-slate-300 select-all bg-slate-100 dark:bg-slate-700 px-1.5 py-0.5 rounded"
          >{{ conversationData.display_id }}</span>
        <div class="flex items-center justify-between flex-1 min-w-0">
          <div class="flex items-center gap-1 min-w-0 flex-1">
            <span
              class="truncate font-semibold text-slate-700 dark:text-slate-200"
              >{{ conversationData.campaign_name }}</span
            >
            <span class="truncate text-slate-500 dark:text-slate-300">{{
              truncatedSenderName
            }}</span>
            <!-- Última mensagem -->
            <span
              v-if="conversationData.last_message"
              class="truncate text-xs text-slate-400 dark:text-slate-500 ml-2"
              :title="conversationData.last_message.content"
            >
              "{{ truncatedLastMessage }}"
            </span>
          </div>
          <span
            class="text-[11px] px-2 py-0.5 rounded-full border border-slate-100 dark:border-slate-800 shadow-sm flex-shrink-0"
            :style="{
              background: conversationStatusBadgeStyle.background,
              color: conversationStatusBadgeStyle.color,
              boxShadow: '0 2px 8px 0 rgba(30,41,59,0.04)',
              border: conversationStatusBadgeStyle.border,
            }"
          >
            {{ conversationData.status }}
          </span>
        </div>
      </div>
    </AgentTooltip>

    <!-- Labels da conversa vinculada -->
    <div
      v-if="
        showLabelsField && !isItemCollapsed && conversationLabels.length > 0
      "
      class="flex flex-wrap gap-1 mb-3"
    >
      <span
        v-for="label in conversationLabels.slice(0, 3)"
        :key="label"
        class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-normal bg-white dark:bg-slate-900 border border-slate-100 dark:border-slate-800 shadow-sm text-slate-700 dark:text-slate-200"
        style="
          box-shadow: 0 2px 8px 0 rgba(30, 41, 59, 0.04);
          min-width: max-content;
        "
      >
        {{ label }}
      </span>
      <span
        v-if="conversationLabels.length > 3"
        class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-normal bg-slate-100 dark:bg-slate-800 border border-slate-100 dark:border-slate-800 shadow-sm text-slate-700 dark:text-slate-200"
        style="
          box-shadow: 0 2px 8px 0 rgba(30, 41, 59, 0.04);
          min-width: max-content;
        "
      >
        +{{ conversationLabels.length - 3 }}
      </span>
    </div>

    <!-- Progress Bar do Checklist -->
    <div
      v-if="showChecklistField && !isItemCollapsed && totalItems > 0"
      class="flex items-center gap-2 mb-3"
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
        class="lucide lucide-loader-icon lucide-loader text-slate-500 flex-shrink-0"
      >
        <path d="M12 2v4" />
        <path d="m16.2 7.8 2.9-2.9" />
        <path d="M18 12h4" />
        <path d="m16.2 16.2 2.9 2.9" />
        <path d="M12 18v4" />
        <path d="m4.9 19.1 2.9-2.9" />
        <path d="M2 12h4" />
        <path d="m4.9 4.9 2.9 2.9" />
      </svg>
      <div class="flex-1">
        <div
          class="h-1.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden"
        >
          <div
            class="h-full bg-woot-500 transition-all duration-300 ease-out"
            :style="{ width: `${checklistProgress}%` }"
          />
        </div>
      </div>
      <span class="text-xs text-slate-500">
        {{ completedItems }}/{{ totalItems }}
      </span>
    </div>

    <div class="flex items-center justify-between">
      <div
        v-if="showAgentField && !isItemCollapsed && item.item_details"
        class="flex items-center gap-2"
      >
        <div class="flex items-center gap-2">
          <!-- Agentes com sobreposição -->
          <div class="flex items-center">
            <AgentTooltip
              v-if="primaryAgent"
              :text="primaryAgent.name"
              class="flex items-center relative"
            >
              <div>
                <Avatar
                  :name="primaryAgent.name"
                  :src="primaryAgent.avatar_url"
                  :size="24"
                  class="flex-shrink-0 cursor-pointer"
                  @click.stop="openAgentAssignModal"
                />
              </div>
            </AgentTooltip>

            <!-- Agentes Adicionais com sobreposição -->
            <AgentTooltip
              v-for="agent in agentInfo.slice(1, 3)"
              :key="agent.id"
              :text="`${agent.name} (clique para remover)`"
              class="flex items-center -ml-2 relative z-10"
              :style="{ zIndex: 10 - agentInfo.slice(1, 3).indexOf(agent) }"
            >
              <Avatar
                :name="agent.name"
                :src="agent.avatar_url"
                :size="24"
                class="flex-shrink-0 cursor-pointer hover:opacity-75 transition-opacity"
                @click.stop="removeAgent(agent.id)"
              />
            </AgentTooltip>

            <!-- Indicador de mais agentes -->
            <div
              v-if="additionalAgentsCount > 2"
              class="flex items-center justify-center w-6 h-6 bg-slate-200 dark:bg-slate-700 rounded-full text-xs font-medium text-slate-600 dark:text-slate-300 cursor-pointer hover:bg-slate-300 dark:hover:bg-slate-600 transition-colors -ml-2 relative z-0"
              @click.stop="openAgentAssignModal"
            >
              +{{ additionalAgentsCount - 2 }}
            </div>
          </div>

          <!-- Botão para adicionar agente quando não há nenhum -->
          <div
            v-if="!primaryAgent"
            class="flex items-center justify-center w-6 h-6 bg-slate-100 dark:bg-slate-800 rounded-full cursor-pointer hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors"
            @click.stop="openAgentAssignModal"
          >
            <fluent-icon
              icon="person-add"
              size="12"
              class="text-slate-500 dark:text-slate-400"
            />
          </div>
        </div>
      </div>

      <!-- Substituir a data pelos ícones -->
      <div
        v-if="showMetadataField"
        class="flex items-center gap-2 text-xs text-slate-500"
      >
        <div v-if="isItemCollapsed" class="flex items-center gap-1">
          <fluent-icon icon="arrow-outwards" size="12" />
        </div>
        <!-- Tempo movido para o cabeçalho -->
        <div v-if="attachmentsCount > 0" class="flex items-center gap-1">
          <fluent-icon icon="attach" size="12" />
          {{ attachmentsCount }}
        </div>
        <div v-if="notesCount > 0" class="flex items-center gap-1">
          <fluent-icon icon="comment-add" size="12" />
          {{ notesCount }}
        </div>

        <!-- Valor do offer -->
        <div
          v-if="showValueField && formattedValue"
          class="flex items-center gap-1 ml-2"
        >
          <span class="text-[11px] font-medium text-slate-500">
            {{ formattedValue }}
          </span>
        </div>

        <!-- Data de agendamento -->
        <div
          v-if="showDeadlineField && formattedDeadline && !isItemCollapsed"
          class="flex items-center gap-1 ml-2"
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
            class="text-slate-500 dark:text-slate-400 flex-shrink-0"
          >
            <path d="M8 2v4" />
            <path d="M16 2v4" />
            <rect width="18" height="18" x="3" y="4" rx="2" />
            <path d="M3 10h18" />
            <path d="m9 16 2 2 4-4" />
          </svg>
          <span class="text-[11px] font-medium text-slate-500">
            {{ formattedDeadline }}
          </span>
        </div>
      </div>
    </div>
  </div>

  <!-- Adicionar o ContextMenu -->
  <CustomContextMenu
    v-if="showContextMenu && isItemVisible"
    :x="contextMenuPosition.x"
    :y="contextMenuPosition.y"
    :show="showContextMenu"
    @close="showContextMenu = false"
  >
    <div
      class="bg-white dark:bg-slate-900 rounded-md shadow-lg border border-slate-100 dark:border-slate-800 w-[170px] min-w-[140px] flex flex-col gap-1"
      style="box-shadow: 0 4px 24px 0 rgba(30, 41, 59, 0.08)"
    >
      <button
        v-if="isStacklab === true"
        class="w-full px-3 py-1.5 text-left text-xs font-normal hover:bg-slate-50 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-200 rounded-none transition-colors"
        @click.stop="handleQuickMessage"
        @mousedown.stop
        @mouseup.stop
      >
        <span class="flex items-center gap-2">
          <fluent-icon icon="chat" size="16" />
          {{ t('KANBAN.CONTEXT_MENU.QUICK_MESSAGE') }}
        </span>
      </button>
      <button
        class="w-full px-3 py-1.5 text-left text-xs font-normal hover:bg-slate-50 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-200 rounded-none transition-colors"
        @click="handleViewContact"
      >
        <span class="flex items-center gap-2">
          <fluent-icon icon="person" size="16" />
          {{ t('KANBAN.CONTEXT_MENU.VIEW_CONTACT') }}
        </span>
      </button>
    </div>
  </CustomContextMenu>

  <!-- Modal de Mensagem Rápida -->
  <Modal
    v-if="isItemVisible"
    v-model:show="showSendMessageModal"
    :on-close="() => (showSendMessageModal = false)"
    :show-close-button="true"
    size="medium"
    :close-on-backdrop-click="false"
    :class="{ 'z-50': showSendMessageModal }"
  >
    <div class="settings-modal">
      <header class="settings-header">
        <h3 class="text-lg font-medium">
          {{ t('KANBAN.SEND_MESSAGE.TITLE') }}
        </h3>
      </header>

      <div class="settings-content">
        <SendMessageTemplate
          :conversation-id="conversationData?.display_id"
          :current-stage="item.funnel_stage || ''"
          :contact="conversationData?.contact"
          :conversation="conversationData"
          :item="item"
          @close="
            () => {
              showSendMessageModal = false;
              showContextMenu.value = false;
            }
          "
          @send="showSendMessageModal = false"
        />
      </div>
    </div>
  </Modal>

  <!-- Modal de Confirmação de Exclusão -->
  <Modal
    v-if="isItemVisible"
    v-model:show="showDeleteModal"
    :on-close="
      () => {
        showDeleteModal = false;
        itemToDelete = null;
      }
    "
  >
    <div class="p-6">
      <h3 class="text-lg font-medium mb-4">Confirmar exclusão</h3>
      <p class="text-sm text-slate-600 dark:text-slate-400 mb-6">
        Tem certeza que deseja excluir o item "{{ itemToDelete?.title }}"?
      </p>
      <div class="flex justify-end space-x-2">
        <Button
          variant="clear"
          color-scheme="secondary"
          @click="showDeleteModal = false"
        >
          Cancelar
        </Button>
        <Button variant="solid" color-scheme="alert" @click="confirmDelete">
          Excluir
        </Button>
      </div>
    </div>
  </Modal>

  <!-- Modal de Status -->
  <Modal
    v-if="isItemVisible"
    v-model:show="showStatusModal"
    :on-close="() => (showStatusModal = false)"
    :show-close-button="true"
    size="small"
  >
    <div
      class="p-4 bg-white dark:bg-slate-900 rounded-md border border-slate-100 dark:border-slate-800 shadow-lg"
    >
      <h3 class="text-lg font-medium mb-4">Atualizar status</h3>
      <div class="space-y-4">
        <div class="flex gap-2">
          <button
            class="flex-1 px-3 py-1.5 border rounded-md text-xs font-normal transition-colors hover:bg-slate-100 dark:hover:bg-slate-800"
            :class="
              statusForm.status === 'open'
                ? 'border-slate-500 bg-slate-50 dark:bg-slate-800 font-bold text-slate-700 dark:text-slate-100'
                : 'border-slate-100 dark:border-slate-800'
            "
            @click="statusForm.status = 'open'"
          >
            <span class="truncate">Em aberto</span>
            <span
              v-if="statusForm.status === 'open'"
              class="ml-2 text-woot-500 text-xs font-semibold"
              >Selecionado</span
            >
          </button>
          <button
            class="flex-1 px-3 py-1.5 border rounded-md text-xs font-normal transition-colors hover:bg-green-50 dark:hover:bg-green-900"
            :class="
              statusForm.status === 'won'
                ? 'border-green-500 bg-green-50 dark:bg-green-900 font-bold text-green-700 dark:text-green-100'
                : 'border-slate-100 dark:border-slate-800'
            "
            @click="statusForm.status = 'won'"
          >
            <span class="truncate">Ganho</span>
            <span
              v-if="statusForm.status === 'won'"
              class="ml-2 text-woot-500 text-xs font-semibold"
              >Selecionado</span
            >
          </button>
          <button
            class="flex-1 px-3 py-1.5 border rounded-md text-xs font-normal transition-colors hover:bg-red-50 dark:hover:bg-red-900"
            :class="
              statusForm.status === 'lost'
                ? 'border-red-500 bg-red-50 dark:bg-red-900 font-bold text-red-700 dark:text-red-100'
                : 'border-slate-100 dark:border-slate-800'
            "
            @click="statusForm.status = 'lost'"
          >
            <span class="truncate">Perdido</span>
            <span
              v-if="statusForm.status === 'lost'"
              class="ml-2 text-woot-500 text-xs font-semibold"
              >Selecionado</span
            >
          </button>
        </div>
        <div v-if="statusForm.status === 'lost'" class="space-y-2">
          <div v-if="lossReasons.length > 0" class="space-y-2">
            <label class="text-sm font-medium">Motivo da perda</label>
            <select
              v-model="statusForm.selectedLossReason"
              class="w-full p-2 border border-slate-100 dark:border-slate-800 rounded-md text-xs bg-white dark:bg-slate-800 focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
            >
              <option :value="null">Selecione um motivo</option>
              <option
                v-for="reason in lossReasons"
                :key="reason.id"
                :value="reason.id"
              >
                {{ reason.title }}
              </option>
              <option value="other">Outro</option>
            </select>
          </div>
          <div
            v-if="
              statusForm.selectedLossReason === 'other' || !lossReasons.length
            "
            class="space-y-2"
          >
            <label class="text-sm font-medium">{{
              lossReasons.length > 0
                ? 'Descreva o motivo'
                : 'Observações adicionais'
            }}</label>
            <textarea
              v-model="statusForm.reason"
              class="w-full p-2 border border-slate-100 dark:border-slate-800 rounded-md text-xs bg-white dark:bg-slate-800 focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
              rows="3"
              :placeholder="
                lossReasons.length > 0
                  ? 'Descreva o motivo da perda'
                  : 'Descreva detalhes adicionais (opcional)'
              "
            />
          </div>
        </div>
        <div v-if="statusForm.status === 'won'" class="space-y-2">
          <div v-if="winReasons.length > 0" class="space-y-2">
            <label class="text-sm font-medium">Motivo do ganho</label>
            <select
              v-model="statusForm.selectedWinReason"
              class="w-full p-2 border border-slate-100 dark:border-slate-800 rounded-md text-xs bg-white dark:bg-slate-800 focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
            >
              <option :value="null">Selecione um motivo</option>
              <option
                v-for="reason in winReasons"
                :key="reason.id"
                :value="reason.id"
              >
                {{ reason.title }}
              </option>
              <option value="other">Outro</option>
            </select>
          </div>
          <div
            v-if="statusForm.selectedWinReason === 'other'"
            class="space-y-2"
          >
            <label class="text-sm font-medium">Descreva o motivo</label>
            <textarea
              v-model="statusForm.reason"
              class="w-full p-2 border border-slate-100 dark:border-slate-800 rounded-md text-xs bg-white dark:bg-slate-800 focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
              rows="3"
              placeholder="Descreva o motivo do ganho"
            />
          </div>
        </div>
        <div
          v-if="statusForm.status === 'won' && availableOffers.length > 0"
          class="space-y-2"
        >
          <label class="text-sm font-medium">Selecione a oferta de fechamento</label>
          <div class="space-y-2 max-h-40 overflow-y-auto">
            <button
              v-for="(offer, index) in availableOffers"
              :key="index"
              type="button"
              class="flex items-center w-full px-3 py-2 rounded-md transition-colors gap-3 border border-slate-100 dark:border-slate-800 text-xs font-normal hover:bg-slate-100 dark:hover:bg-slate-800"
              :class="[
                statusForm.selectedOffer === offer
                  ? 'border-green-500 bg-green-50 dark:bg-green-900/30 font-bold text-green-700 dark:text-green-300'
                  : '',
              ]"
              @click="statusForm.selectedOffer = offer"
            >
              <div class="flex flex-col items-start flex-1 min-w-0">
                <div class="flex items-center gap-2 w-full">
                  <span class="font-medium truncate">{{
                    offer.description || 'Oferta sem descrição'
                  }}</span>
                  <span
                    class="text-green-600 dark:text-green-400 font-semibold text-xs"
                  >
                    {{
                      new Intl.NumberFormat(offer.currency?.locale || 'pt-BR', {
                        style: 'currency',
                        currency: offer.currency?.code || 'BRL',
                      }).format(offer.value || 0)
                    }}
                  </span>
                </div>
              </div>
              <span
                v-if="statusForm.selectedOffer === offer"
                class="text-green-500 text-xs font-semibold flex-shrink-0"
                >Selecionada</span
              >
            </button>
            <div
              v-if="availableOffers.length === 0"
              class="px-3 py-2 text-slate-400 text-xs text-center"
            >
              Nenhuma oferta disponível
            </div>
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-4">
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            @click="showStatusModal = false"
          >
            Cancelar
          </Button>
          <Button
            variant="solid"
            color="blue"
            size="sm"
            :disabled="
              statusForm.status === 'won' &&
              availableOffers.length > 0 &&
              !statusForm.selectedOffer
            "
            @click="handleStatusSave"
          >
            Salvar
          </Button>
        </div>
      </div>
    </div>
  </Modal>

  <!-- Modal de Visibilidade dos Campos -->
  <Modal
    v-if="isItemVisible"
    v-model:show="showVisibilityModal"
    :on-close="() => (showVisibilityModal = false)"
    :show-close-button="true"
    size="medium"
  >
    <div class="settings-modal">
      <header class="settings-header">
        <h3 class="text-lg font-medium">
          {{ t('KANBAN.CONTEXT_MENU.CUSTOMIZE_FIELDS.TITLE') }}
        </h3>
      </header>
      <div class="settings-content">
        <p class="text-sm text-slate-600 dark:text-slate-400 mb-4">
          {{ t('KANBAN.CONTEXT_MENU.CUSTOMIZE_FIELDS.DESCRIPTION') }}
        </p>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <!-- Coluna 1 -->
          <div class="space-y-4">
            <label
              class="flex items-center p-2 rounded hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer transition-colors"
            >
              <input
                v-model="showDescriptionField"
                type="checkbox"
                class="form-checkbox h-4 w-4 text-woot-500"
              />
              <span class="ml-2 text-sm">
                <span class="font-medium">{{
                  t('KANBAN.FORM.DESCRIPTION.LABEL')
                }}</span>
                <span
                  class="inline-block ml-2 px-2.5 py-1 text-[10px] font-semibold bg-indigo-100 text-indigo-700 dark:bg-indigo-800 dark:text-indigo-100 rounded-md border border-indigo-200 dark:border-indigo-700 shadow-sm"
                  >{{
                    t(
                      'KANBAN.CONTEXT_MENU.CUSTOMIZE_FIELDS.VISIBLE_WHEN_COLLAPSED'
                    )
                  }}</span
                >
                <span class="block text-xs text-slate-500"
                  >Detalhes do card</span
                >
              </span>
            </label>

            <label
              class="flex items-center p-2 rounded hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer transition-colors"
            >
              <input
                v-model="showLabelsField"
                type="checkbox"
                class="form-checkbox h-4 w-4 text-woot-500"
              />
              <span class="ml-2 text-sm">
                <span class="font-medium">Etiquetas</span>
                <span class="block text-xs text-slate-500"
                  >Tags da conversa</span
                >
              </span>
            </label>

            <label
              class="flex items-center p-2 rounded hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer transition-colors"
            >
              <input
                v-model="showPriorityField"
                type="checkbox"
                class="form-checkbox h-4 w-4 text-woot-500"
              />
              <span class="ml-2 text-sm">
                <span class="font-medium">{{
                  t('KANBAN.FORM.PRIORITY.LABEL')
                }}</span>
                <span class="block text-xs text-slate-500"
                  >{{ t('KANBAN.PRIORITY_LABELS.HIGH') }},
                  {{ t('KANBAN.PRIORITY_LABELS.MEDIUM') }},
                  {{ t('KANBAN.PRIORITY_LABELS.LOW') }}</span
                >
              </span>
            </label>

            <label
              class="flex items-center p-2 rounded hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer transition-colors"
            >
              <input
                v-model="showValueField"
                type="checkbox"
                class="form-checkbox h-4 w-4 text-woot-500"
              />
              <span class="ml-2 text-sm">
                <span class="font-medium">{{
                  t('KANBAN.FORM.VALUE.LABEL')
                }}</span>
                <span class="block text-xs text-slate-500">{{
                  t('KANBAN.FORM.VALUE.LABEL')
                }}</span>
              </span>
            </label>
          </div>

          <!-- Coluna 2 -->
          <div class="space-y-4">
            <label
              class="flex items-center p-2 rounded hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer transition-colors"
            >
              <input
                v-model="showDeadlineField"
                type="checkbox"
                class="form-checkbox h-4 w-4 text-woot-500"
              />
              <span class="ml-2 text-sm">
                <span class="font-medium">{{ t('KANBAN.DEADLINE') }}</span>
                <span class="block text-xs text-slate-500">{{
                  t('KANBAN.DEADLINE_DESCRIPTION')
                }}</span>
              </span>
            </label>

            <label
              class="flex items-center p-2 rounded hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer transition-colors"
            >
              <input
                v-model="showConversationField"
                type="checkbox"
                class="form-checkbox h-4 w-4 text-woot-500"
              />
              <span class="ml-2 text-sm">
                <span class="font-medium">{{
                  t('KANBAN.ITEM_CONVERSATION.TITLE')
                }}</span>
                <span class="block text-xs text-slate-500">{{
                  t('KANBAN.ITEM_CONVERSATION.DESCRIPTION')
                }}</span>
              </span>
            </label>

            <label
              class="flex items-center p-2 rounded hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer transition-colors"
            >
              <input
                v-model="showChecklistField"
                type="checkbox"
                class="form-checkbox h-4 w-4 text-woot-500"
              />
              <span class="ml-2 text-sm">
                <span class="font-medium">Checklist</span>
                <span class="block text-xs text-slate-500"
                  >Progresso das tarefas</span
                >
              </span>
            </label>

            <label
              class="flex items-center p-2 rounded hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer transition-colors"
            >
              <input
                v-model="showAgentField"
                type="checkbox"
                class="form-checkbox h-4 w-4 text-woot-500"
              />
              <span class="ml-2 text-sm">
                <span class="font-medium">Agente</span>
                <span class="block text-xs text-slate-500"
                  >Responsável atribuído</span
                >
              </span>
            </label>
          </div>
        </div>

        <div class="mt-4 pt-4 border-t border-slate-100 dark:border-slate-700">
          <label
            class="flex items-center p-2 rounded hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer transition-colors"
          >
            <input
              v-model="showMetadataField"
              type="checkbox"
              class="form-checkbox h-4 w-4 text-woot-500"
            />
            <span class="ml-2 text-sm">
              <span class="font-medium">Metadados</span>
              <span class="block text-xs text-slate-500"
                >Tempo na etapa, anexos e notas</span
              >
            </span>
          </label>
        </div>

        <div class="flex justify-between mt-6">
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            @click="
              () => {
                showDescriptionField = true;
                showLabelsField = true;
                showPriorityField = true;
                showValueField = true;
                showDeadlineField = true;
                showConversationField = true;
                showChecklistField = true;
                showAgentField = true;
                showMetadataField = true;
              }
            "
          >
            Restaurar padrão
          </Button>
          <Button
            variant="solid"
            color="blue"
            size="sm"
            @click="showVisibilityModal = false"
          >
            Fechar
          </Button>
        </div>
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
      <h3 class="text-lg font-medium mb-4">Gerenciar Agentes Atribuídos</h3>

      <!-- Seção de agentes já atribuídos -->
      <div v-if="agentInfo.length > 0" class="mb-4">
        <h4 class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">
          Agentes Atribuídos ({{ agentInfo.length }})
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
                :src="agent.avatar_url || agent.thumbnail || ''"
                :size="24"
              />
              <div>
                <div
                  class="text-sm font-medium text-slate-900 dark:text-slate-100"
                >
                  {{ agent.name }}
                </div>
                <div class="text-xs text-slate-500 dark:text-slate-400">
                  Atribuído em
                  {{ new Date(agent.assigned_at).toLocaleDateString('pt-BR') }}
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
        <h4 class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">
          Adicionar Novo Agente
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
              agentInfo.some(a => a.id === agent.id)
                ? 'opacity-50 cursor-not-allowed'
                : '',
            ]"
            :disabled="agentInfo.some(a => a.id === agent.id)"
            @click="selectedAgentId = agent.id"
          >
            <Avatar
              :name="agent.name || 'Agente'"
              :src="agent.avatar_url || agent.thumbnail || ''"
              :size="24"
              class="mr-2"
            />
            <span class="truncate">{{ agent.name || 'Agente' }}</span>
            <span
              v-if="agentInfo.some(a => a.id === agent.id)"
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
          @click="showAgentAssignModal = false"
        >
          Fechar
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
          Adicionar Agente
        </Button>
      </div>
    </div>
  </Modal>

  <!-- Modal de seleção de prioridade -->
  <Modal
    v-model:show="showPriorityModal"
    :on-close="() => (showPriorityModal = false)"
    :show-close-button="true"
    size="small"
  >
    <div
      class="p-4 bg-white dark:bg-slate-900 rounded-md border border-slate-100 dark:border-slate-800 shadow-lg"
    >
      <h3 class="text-lg font-medium mb-4">Definir prioridade</h3>
      <div class="space-y-2 mb-4">
        <button
          v-for="option in [
            { value: 'urgent', label: 'Urgente' },
            { value: 'high', label: 'Alta' },
            { value: 'medium', label: 'Média' },
            { value: 'low', label: 'Baixa' },
            { value: 'none', label: 'Nenhuma' },
          ]"
          :key="option.value"
          type="button"
          class="flex items-center w-full px-3 py-1.5 rounded-md transition-colors gap-2 border border-slate-100 dark:border-slate-800 text-xs font-normal hover:bg-slate-100 dark:hover:bg-slate-800"
          :class="[
            selectedPriority === option.value
              ? 'border-woot-500 bg-woot-50 dark:bg-woot-900/30 font-bold text-woot-600'
              : '',
          ]"
          @click="selectedPriority = option.value"
        >
          <span class="truncate">{{ option.label }}</span>
          <span
            v-if="selectedPriority === option.value"
            class="ml-auto text-woot-500 text-xs font-semibold"
            >Selecionado</span
          >
        </button>
      </div>
      <div class="flex justify-end gap-2 mt-4">
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          @click="showPriorityModal = false"
        >
          Cancelar
        </Button>
        <Button
          variant="solid"
          color="blue"
          size="sm"
          :is-loading="priorityAssignLoading"
          :disabled="priorityAssignLoading"
          @click="assignPriority"
        >
          Confirmar
        </Button>
      </div>
    </div>
  </Modal>
</template>

<style lang="scss" scoped>
.flex {
  &:first-child {
    margin-top: 0;
  }
}

.settings-modal {
  @apply flex flex-col;

  .settings-header {
    @apply p-4 border-b border-slate-100 dark:border-slate-700;
  }

  .settings-content {
    @apply p-4 space-y-4;
  }
}

// Garantir alinhamento correto entre avatar e priority circle
:deep(.avatar-component) {
  display: flex;
  align-items: center;
  justify-content: center;
}

:deep(.priority-circle) {
  display: flex;
  align-items: center;
  justify-content: center;
}

// Estilos para markdown renderizado
.prose {
  font-size: 12px !important;
  @apply leading-relaxed;

  :deep(p) {
    @apply mb-1 last:mb-0;
    font-size: 12px !important;
  }

  :deep(ul) {
    @apply list-disc list-inside mb-1 space-y-1;
  }

  :deep(ol) {
    @apply list-decimal list-inside mb-1 space-y-1;
  }

  :deep(li) {
    @apply leading-relaxed;
    font-size: 12px !important;
  }

  :deep(strong) {
    @apply font-semibold;
    font-size: 12px !important;
  }

  :deep(em) {
    @apply italic;
    font-size: 12px !important;
  }

  :deep(code) {
    @apply bg-slate-100 dark:bg-slate-800 px-1 py-0.5 rounded font-mono;
    font-size: 12px !important;
  }

  :deep(pre) {
    @apply bg-slate-100 dark:bg-slate-800 p-2 rounded font-mono overflow-x-auto mb-1;
    font-size: 12px !important;
  }

  :deep(a) {
    @apply text-woot-500 hover:text-woot-600 underline;
    font-size: 12px !important;
  }
}
</style>
