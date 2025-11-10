<script setup>
import { computed, ref, onMounted, watch, nextTick, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import conversationAPI from '../../../../api/inbox/conversation';
import KanbanAPI from '../../../../api/kanban';
import contacts from '../../../../api/contacts';
import { useStore } from 'vuex';
import { formatDistanceToNow, format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { emitter } from 'shared/helpers/mitt';
import { useRouter } from 'vue-router';
import Modal from 'dashboard/components/Modal.vue';
import SendMessageTemplate from './SendMessageTemplate.vue';
import FunnelSelector from './FunnelSelector.vue';
import messageAPI from '../../../../api/inbox/message';
import { useConfig } from 'dashboard/composables/useConfig';
import KanbanAgentInfo from './KanbanAgentInfo.vue';
import KanbanTabs from './KanbanTabs.vue';
import KanbanBasicDataPanel from './KanbanBasicDataPanel.vue';
import KanbanActivitiesTab from './KanbanActivitiesTab.vue';

const props = defineProps({
  itemId: {
    type: [Number, String],
    required: true,
  },
  forceReload: {
    type: Number,
    default: 0,
  },
  activeTab: {
    type: String,
    default: 'basic_data',
  },
  showHeader: {
    type: Boolean,
    default: false,
  },
  showEditButton: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits([
  'update:item',
  'item-updated',
  'close',
  'edit',
  'deleted',
  'navigate-to-conversation',
  'context-menu',
  'stage-click',
]);

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { isStacklab } = useConfig();
const item = ref(null);
const isLoading = ref(true);
const error = ref(null);
const showItemSelector = ref(false);
const showConversationSelector = ref(false);
const showContactSelector = ref(false);
const kanbanItems = ref([]);
const conversations = ref([]);
const loadingItems = ref(false);
const loadingConversations = ref(false);
const selectedItemId = ref(null);
const selectedConversationId = ref(null);
const selectedContactId = ref(null);
const currentActiveTab = ref(props.activeTab);

// Checklist items será gerenciado pelas abas individuais

// Adicionar variáveis faltantes para as abas
const contactsList = ref([]);
const loadingContacts = ref(false);

const currentStageName = computed(() => {
  const currentFunnel = store.getters['funnel/getSelectedFunnel'];
  if (!currentFunnel?.stages || !item.value?.funnel_stage) return '';

  return (
    currentFunnel.stages[item.value?.funnel_stage]?.name ||
    item.value?.funnel_stage
  );
});

// Novo computed para extrair o progresso nas etapas
const stageProgress = computed(() => {
  // Busca as etapas no local esperado ou alternativo
  const stages =
    item.value?.item_details?.funnel?.stages ||
    store.getters['funnel/getSelectedFunnel']?.stages ||
    null;
  const activities = item.value?.activities || [];

  if (!stages || !activities.length) {
    return {
      stages: [],
      currentStageIndex: -1,
      completedStages: [],
      stageTransitions: [],
    };
  }

  // Converte stages object para array ordenado por position
  const stagesArray = Object.entries(stages)
    .map(([key, stage]) => ({
      key,
      name: stage.name,
      color: stage.color,
      position: stage.position,
    }))
    .sort((a, b) => a.position - b.position);

  // Extrai as mudanças de etapa das atividades
  const stageChanges = activities
    .filter(activity => activity.type === 'stage_changed')
    .sort((a, b) => new Date(a.created_at) - new Date(b.created_at));

  // Encontra todas as etapas pelas quais o item passou
  const visitedStages = new Set();
  stageChanges.forEach(change => {
    if (change.details.new_stage) {
      visitedStages.add(change.details.new_stage);
    }
  });

  // Etapa atual
  const currentStage = item.value?.funnel_stage;
  const currentStageIndex = stagesArray.findIndex(
    stage => stage.key === currentStage
  );

  // Determina etapas completadas baseado na ordem das posições
  const completedStages = [];
  if (currentStageIndex >= 0) {
    for (let i = 0; i < currentStageIndex; i++) {
      if (visitedStages.has(stagesArray[i].key)) {
        completedStages.push(stagesArray[i].key);
      }
    }
  }

  // Cria transições apenas entre etapas consecutivas na timeline visual
  const stageTransitions = [];

  // Para cada par de etapas consecutivas na timeline (0-1, 1-2, 2-3, etc.)
  for (let i = 0; i < stagesArray.length - 1; i++) {
    const fromStage = stagesArray[i];
    const toStage = stagesArray[i + 1];
    const transitionKey = `${i}-${i + 1}`;

    // Encontra a transição mais recente entre essas duas etapas consecutivas
    let latestTransition = null;
    let latestDate = null;

    for (const change of stageChanges) {
      if (!change.details?.old_stage || !change.details?.new_stage) continue;

      // Verifica se essa mudança representa uma transição entre as etapas consecutivas atuais
      if (
        change.details.old_stage === fromStage.key &&
        change.details.new_stage === toStage.key
      ) {
        const changeDate = new Date(
          change.details.created_at || change.created_at
        );

        if (!latestDate || changeDate > latestDate) {
          latestDate = changeDate;
          latestTransition = {
            fromStage: fromStage.key,
            toStage: toStage.key,
            fromIndex: i,
            toIndex: i + 1,
            user: change.user || change.details?.user,
            created_at: change.created_at,
            key: transitionKey,
          };
        }
      }
    }

    // Só adiciona se encontrou pelo menos uma transição
    if (latestTransition) {
      stageTransitions.push(latestTransition);
    }
  }

  return {
    stages: stagesArray,
    currentStageIndex,
    completedStages,
    currentStage,
    visitedStages: Array.from(visitedStages),
    stageTransitions,
  };
});

const currentUser = computed(() => store.getters.getCurrentUser);
const fetchItemDetails = async () => {
  try {
    isLoading.value = true;
    error.value = null;

    const { data } = await KanbanAPI.getItem(props.itemId);
    item.value = data;

    // Dados completos serão buscados pelas abas individuais quando necessário
    // O show retorna apenas metadados para performance

    // Inicializar agentData se já estiver nos dados
    if (data.assigned_agents?.length > 0) {
      agentData.value = data.assigned_agents[0];
    } else if (data.agent) {
      agentData.value = data.agent;
    }

    // Buscar dados relacionados apenas se necessário
    await Promise.all([fetchKanbanItems()]);
  } catch (err) {
    error.value = err;
  } finally {
    isLoading.value = false;
  }
};

const prepareItemForDetails = item => {
  return {
    id: item.id || null,
    title: item.title || '',
    description: item.description || '',
    priority: item.priority || 'none',
    funnel_id: item.funnel_id || null,
    funnel_stage: item.funnel_stage || null,
    position: item.position || 0,
    item_details: {
      ...{
        title: '',
        description: '',
        priority: 'none',
        value: null,
        currency: 'BRL',
        deadline_at: null,
        scheduling_type: null,
        scheduled_at: null,
        agent_id: null,
        rescheduled: false,
        rescheduling_history: [],
        notes: [],
      },
      ...(item.item_details || {}),
    },
    stageName: item.stageName || '',
    stageColor: item.stageColor || '#64748B',
    created_at: item.created_at || new Date().toISOString(),
    custom_attributes: item.custom_attributes || {},
    checklist: item.checklist || [],
    // agent não é mais usado, apenas assigned_agents
  };
};

const fetchKanbanItems = async () => {
  try {
    loadingItems.value = true;
    const response = await KanbanAPI.getItems();
    const responseData = response.data;

    let items = [];
    if (responseData && responseData.items) {
      // Nova estrutura paginada
      items = responseData.items;
    } else if (Array.isArray(responseData)) {
      // Estrutura antiga (array direto)
      items = responseData;
    }

    kanbanItems.value = items.map(item => ({
      id: item.id,
      title: item.item_details?.title || t('KANBAN.UNTITLED_ITEM'),
      description: item.item_details?.description,
      value: item.item_details?.value,
      priority: item.item_details?.priority,
      stage: item.funnel_stage,
    }));
  } catch (error) {
    // Handle error silently
  } finally {
    loadingItems.value = false;
  }
};

const priorityInfo = computed(() => {
  // Buscar prioridade do item_details
  const priority = item.value?.item_details?.priority?.toLowerCase() || 'none';

  // Se for none, retorna null para não exibir o badge
  if (priority === 'none') return null;

  const priorityMap = {
    urgent: {
      label: t('KANBAN.PRIORITY_LABELS.URGENT') || 'Urgente',
      class: 'bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200',
    },
    high: {
      label: t('KANBAN.PRIORITY_LABELS.HIGH'),
      class: 'bg-n-ruby-3 dark:bg-n-ruby-8 text-n-ruby-9 dark:text-n-ruby-1',
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
  };

  return priorityMap[priority] || null;
});

const priorityClass = computed(() => {
  const priorityMap = {
    urgent: 'bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200',
    high: 'bg-n-ruby-3 dark:bg-n-ruby-8 text-n-ruby-9 dark:text-n-ruby-1',
    medium:
      'bg-yellow-50 dark:bg-yellow-800 text-yellow-800 dark:text-yellow-50',
    low: 'bg-green-50 dark:bg-green-800 text-green-800 dark:text-green-50',
    none: 'bg-slate-50 dark:bg-slate-800 text-slate-800 dark:text-slate-50',
  };
  return (
    priorityMap[item.value?.item_details?.priority?.toLowerCase() || 'none'] ||
    priorityMap.none
  );
});

const formattedValue = computed(() => {
  if (!item.value?.item_details?.value) return null;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(item.value?.item_details?.value);
});

// Ref para armazenar os dados do agente
const agentData = ref(null);
const loadingAgent = ref(false);

const fetchAgent = async agentId => {
  if (!agentId) return;

  try {
    loadingAgent.value = true;

    // Se houver assigned_agents, usa o primeiro
    if (item.value?.assigned_agents?.length > 0) {
      agentData.value = item.value?.assigned_agents[0];
    }
    // Fallback para store (opcional)
    else {
      const storeAgents =
        store.getters['funnel/getSelectedFunnel']?.settings?.agents || [];
      agentData.value = storeAgents.find(agent => agent.id === agentId) || null;
    }
  } catch (error) {
    // Handle error silently
  } finally {
    loadingAgent.value = false;
  }
};

const agentInfo = computed(() => {
  if (!agentData.value) return null;

  return {
    name: agentData.value.name,
    avatar_url: agentData.value.avatar_url || agentData.value.thumbnail || '',
  };
});

// Ref para armazenar os dados da conversa
const conversationData = computed(() => {
  return item.value?.conversation || null;
});
const loadingConversation = ref(false);

const fetchConversationData = async conversationId => {
  if (!conversationId) return;

  try {
    loadingConversation.value = true;
    // Se a conversa já estiver nos detalhes do item, use-a
    if (item.value?.conversation) {
      conversationData.value = item.value?.conversation;
    } else {
      // Fallback para API apenas se necessário
      const response = await conversationAPI.get({
        assigneeType: ['all'],
        status: ['open', 'pending', 'resolved'],
      });
      const conversations = response.data.data.payload;
      conversationData.value = conversations.find(c => c.id === conversationId);
    }
  } catch (error) {
    // Handle error silently
  } finally {
    loadingConversation.value = false;
  }
};

// Notes e attachments serão gerenciados pelas abas individuais
const noteAttachments = ref([]);
const selectedFileName = ref('');

const registerActivity = async (type, details) => {
  try {
    const newActivity = {
      id: Date.now(),
      type,
      details,
      created_at: new Date().toISOString(),
      user: {
        id: currentUser.value.id,
        name: currentUser.value.name,
        avatar_url: currentUser.value.avatar_url,
      },
    };

    const existingActivities = Array.isArray(item.value?.activities)
      ? item.value.activities
      : [];
    const activities = [...existingActivities, newActivity];

    const payload = {
      ...(item.value || {}),
      item_details: {
        ...(item.value?.item_details || {}),
        activities,
      },
    };

    const { data } = await KanbanAPI.updateItem(item.value?.id, payload);
    item.value = data;
    emit('update:item', data);
    emit('item-updated');
  } catch (error) {
    // Handle error silently
  }
};

// Watchers para notes e checklist serão gerenciados pelas abas individuais

const fetchConversations = async () => {
  try {
    loadingConversations.value = true;
    const response = await conversationAPI.get({});

    conversations.value = response.data.data.payload.map(conversation => ({
      id: conversation.id,
      title:
        conversation.meta.sender.name ||
        conversation.meta.sender.email ||
        t('KANBAN.ITEM_CONVERSATION.NO_CONTACT'),
      description: conversation.messages[0]?.content || t('KANBAN.NO_MESSAGES'),
      unread_count: conversation.unread_count,
      created_at: new Date(conversation.created_at).toLocaleDateString(),
      channel_type: conversation.channel_type,
      status: conversation.status,
    }));
  } catch (error) {
    // Handle error silently
  } finally {
    loadingConversations.value = false;
  }
};

const selectConversation = conversation => {
  selectedConversationId.value = conversation.id;
  showConversationSelector.value = false;
};

const fetchContacts = async () => {
  try {
    loadingContacts.value = true;
    const response = await contacts.get();
    contactsList.value = response.data?.payload || [];
  } catch (error) {
    // Handle error silently
  } finally {
    loadingContacts.value = false;
  }
};

const selectContact = contact => {
  selectedContactId.value = contact.id;
  showContactSelector.value = false;
};

const getLinkedItemDetails = itemId => {
  return kanbanItems.value.find(item => item.id === itemId);
};

const selectItem = item => {
  selectedItemId.value = item.id;
  showItemSelector.value = false;
};

const fetchNoteConversationData = async conversationId => {
  if (!conversationId) return null;

  try {
    const response = await conversationAPI.get({});
    const conversations = response.data.data.payload;
    return conversations.find(c => c.id === conversationId);
  } catch (error) {
    return null;
  }
};

const fetchNoteContactData = async contactId => {
  if (!contactId) return null;

  try {
    const response = await contacts.get();
    const contactsList = response.data?.payload;
    return contactsList.find(c => c.id === contactId);
  } catch (error) {
    return null;
  }
};

const fetchNoteItemData = async itemId => {
  if (!itemId) return null;

  try {
    if (kanbanItems.value.length === 0) {
      await fetchKanbanItems();
    }
    return kanbanItems.value.find(item => item.id === itemId);
  } catch (error) {
    return null;
  }
};

const getNoteLinkData = async note => {
  const linkData = {};

  if (note.linked_item_id) {
    linkData.item = await fetchNoteItemData(note.linked_item_id);
  }

  if (note.linked_conversation_id) {
    linkData.conversation = await fetchNoteConversationData(
      note.linked_conversation_id
    );
  }

  if (note.linked_contact_id) {
    linkData.contact = await fetchNoteContactData(note.linked_contact_id);
  }

  return linkData;
};

const toggleItemSelector = () => {
  if (showItemSelector.value) {
    showItemSelector.value = false;
  } else {
    showItemSelector.value = true;
    showConversationSelector.value = false;
    showContactSelector.value = false;
  }
};

const toggleConversationSelector = () => {
  if (showConversationSelector.value) {
    showConversationSelector.value = false;
  } else {
    showConversationSelector.value = true;
    showItemSelector.value = false;
    showContactSelector.value = false;
  }
};

const toggleContactSelector = () => {
  if (showContactSelector.value) {
    showContactSelector.value = false;
  } else {
    showContactSelector.value = true;
    showItemSelector.value = false;
    showConversationSelector.value = false;
  }
};

const itemButtonText = computed(() => {
  if (showItemSelector.value) {
    return t('KANBAN.CANCEL');
  }

  if (selectedItemId.value) {
    const selectedItem = kanbanItems.value.find(
      item => item.id === selectedItemId.value
    );
    return selectedItem?.title || t('KANBAN.FORM.NOTES.LINK_ITEM');
  }

  return t('KANBAN.FORM.NOTES.LINK_ITEM');
});

const conversationButtonText = computed(() => {
  if (showConversationSelector.value) {
    return t('KANBAN.CANCEL');
  }

  if (selectedConversationId.value) {
    const selectedConversation = conversations.value.find(
      conv => conv.id === selectedConversationId.value
    );
    return selectedConversation
      ? `#${selectedConversation.id} - ${selectedConversation.title}`
      : t('KANBAN.FORM.NOTES.LINK_CONVERSATION');
  }

  return t('KANBAN.FORM.NOTES.LINK_CONVERSATION');
});

const contactButtonText = computed(() => {
  if (showContactSelector.value) {
    return t('KANBAN.CANCEL');
  }

  if (selectedContactId.value) {
    const selectedContact = contactsList.value.find(
      contact => contact.id === selectedContactId.value
    );
    return selectedContact?.name || t('KANBAN.FORM.NOTES.LINK_CONTACT');
  }

  return t('KANBAN.FORM.NOTES.LINK_CONTACT');
});

const checklistItemButtonText = computed(() => {
  if (showItemSelector.value) {
    return t('KANBAN.CANCEL');
  }

  if (selectedItemId.value) {
    const selectedItem = kanbanItems.value.find(
      item => item.id === selectedItemId.value
    );
    return selectedItem?.title || t('KANBAN.FORM.NOTES.LINK_ITEM');
  }

  return t('KANBAN.FORM.NOTES.LINK_ITEM');
});

// Computed para obter a lista de agentes
const agentList = computed(() => store.getters['agents/getAgents']);

// Modifique a função handleNoteAttachment para atualizar o nome do arquivo
const handleNoteAttachment = async file => {
  if (!file) return;

  // Atualiza o nome do arquivo selecionado
  selectedFileName.value = file.file.name;

  if (!item.value?.id) {
    return;
  }

  isUploadingAttachment.value = true;
  try {
    if (checkFileSizeLimit(file, MAXIMUM_FILE_UPLOAD_SIZE)) {
      const formData = new FormData();
      formData.append('attachment', file.file);

      const url = `/api/v1/accounts/${store.getters.getCurrentAccountId}/kanban/items/${item.value?.id}/note_attachments`;

      const response = await axios.post(url, formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      });

      const newAttachment = {
        id: response.data.id.toString(),
        url: response.data.attachment_url,
        filename: file.file.name,
        fileType: file.file.type || 'application/octet-stream',
        source: {
          type: 'note',
          id: Date.now(),
        },
      };

      // Adiciona o anexo à lista de anexos da nota atual
      const currentAttachments = Array.isArray(noteAttachments.value)
        ? noteAttachments.value
        : [];
      noteAttachments.value = [...currentAttachments, newAttachment];
    }
  } catch (error) {
    // Handle error silently
  } finally {
    isUploadingAttachment.value = false;
  }
};

// Adicione a função formatDate
const formatDate = date => {
  if (!date) return '';
  try {
    return format(new Date(date), 'dd/MM/yyyy HH:mm', { locale: ptBR });
  } catch (error) {
    return '';
  }
};

onMounted(() => {
  // Buscar dados do item
  fetchItemDetails();

  // Adicionar listener para fechar selects ao clicar fora
  const handleClickOutside = event => {
    const target = event.target;
    const isItemSelector = target.closest('.item-selector');
    const isConversationSelector = target.closest('.conversation-selector');
    const isContactSelector = target.closest('.contact-selector');
    const isActionButton = target.closest('.action-button');

    if (!isItemSelector && !isActionButton && showItemSelector.value) {
      showItemSelector.value = false;
    }
    if (
      !isConversationSelector &&
      !isActionButton &&
      showConversationSelector.value
    ) {
      showConversationSelector.value = false;
    }
    if (!isContactSelector && !isActionButton && showContactSelector.value) {
      showContactSelector.value = false;
    }
  };

  document.addEventListener('mousedown', handleClickOutside);

  onUnmounted(() => {
    document.removeEventListener('mousedown', handleClickOutside);
  });
});

// Adicione a função para formatar o valor em BRL
const formatCurrency = value => {
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(value);
};

// Função para formatar moeda de oferta usando dados específicos da oferta
const formatCurrencyForOffer = (value, currency) => {
  if (currency && currency.locale && currency.code) {
    return new Intl.NumberFormat(currency.locale, {
      style: 'currency',
      currency: currency.code,
    }).format(value);
  }

  // Fallback para formatação padrão
  return formatCurrency(value);
};

// Notes serão gerenciados pelas abas individuais

// Checklists serão gerenciados pelas abas individuais

// Adicione uma função para navegar para uma conversa
const navigateToConversation = (e, conversationId) => {
  e.stopPropagation();
  if (!conversationId) return;

  // Obter o account_id de forma mais segura
  const accountId = store.getters.getCurrentAccountId;

  try {
    router.push({
      name: 'inbox_conversation_through_inbox',
      params: {
        accountId,
        conversationId,
      },
    });
  } catch (error) {
    // Fallback: navegação direta pela URL com account_id atual
    window.location.href = `/app/accounts/${accountId}/conversations/${conversationId}`;
  }
};

// Adicione uma função para lidar com o contexto do menu
const handleContextMenu = (e, conversationId) => {
  if (!conversationId || !conversationData.value) return;

  e.preventDefault();
  showContextMenu.value = true;
  contextMenuPosition.value = {
    x: e.clientX,
    y: e.clientY,
  };
};

const showContextMenu = ref(false);
const contextMenuPosition = ref({ x: 0, y: 0 });
const showSendMessageModal = ref(false);
const showStageMoveModal = ref(false);
const selectedStageForMove = ref(null);

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

const handleSendMessage = ({ template, conversationId }) => {
  showSendMessageModal.value = false;
};

const handleViewContact = () => {
  // Fecha o menu de contexto
  showContextMenu.value = false;

  // Verifica se temos os dados necessários
  if (!item.value?.conversation?.id) {
    return;
  }

  const accountId = store.getters.getCurrentAccountId;
  const conversationId = item.value?.conversation.id;

  try {
    // Navega para a conversa usando a mesma rota do card
    router.push({
      name: 'inbox_conversation_through_inbox',
      params: {
        accountId,
        conversationId,
      },
    });
  } catch (err) {
    // Fallback: navegação direta pela URL
    window.location.href = `/app/accounts/${accountId}/conversations/${conversationId}`;
  }
};

// Adicione este watch
watch(showSendMessageModal, newValue => {
  if (!newValue) {
    nextTick(() => {
      showContextMenu.value = false;
    });
  }
});

// Adicione este computed
const truncatedConversationTitle = computed(() => {
  const title =
    conversationData.value?.contact?.name ||
    conversationData.value?.contact?.email ||
    '';
  return title.length > 17 ? `${title.substring(0, 10)}...` : title;
});

// Adicione este computed para lidar com a descrição
const itemDescription = computed(() => {
  return item.value?.item_details?.description || item.value?.description || '';
});

// Computed para extrair dados da conversa diretamente do item
const conversationFromItem = computed(() => {
  // Primeiro tenta usar os dados da conversa do item (preferência)
  const conversationData = item.value?.conversation;
  if (conversationData) {
    return {
      id: conversationData.id,
      display_id: conversationData.display_id,
      status: conversationData.status,
      last_activity_at: conversationData.last_activity_at,
      unread_count: conversationData.unread_count,
      label_list: conversationData.label_list || [],
      contact: conversationData.contact,
      inbox: conversationData.inbox,
    };
  }

  // Fallback para a prop conversationData (compatibilidade)
  if (props.conversationData) {
    return props.conversationData;
  }

  return null;
});

// Computed para dados combinados da conversa (prioriza dados do item)
const conversationInfo = computed(() => {
  return conversationFromItem.value;
});

const newMessage = ref('');

// Função para enviar mensagem (mock)
const sendMessage = async message => {
  try {
    // Verificar se a mensagem é válida
    if (!message || (typeof message === 'object' && !message.target?.value)) {
      return;
    }

    const content =
      typeof message === 'object' ? message.target.value : message;

    const payload = {
      content: content,
      private: false,
      echo_id: Date.now().toString(),
      cc_emails: '',
      bcc_emails: '',
      to_emails: '',
    };

    // Verificar se a conversa existe
    if (!item.value?.item_details?.conversation?.id) {
      return;
    }

    const { data } = await messageAPI.create({
      conversationId: item.value?.conversation.id,
      message: payload.content,
      private: payload.private,
      echo_id: payload.echo_id,
      cc_emails: payload.cc_emails,
      bcc_emails: payload.bcc_emails,
      to_emails: payload.to_emails,
    });

    messages.value.push({
      id: data.id,
      text: payload.content,
      isMe: true,
      timestamp: new Date().toISOString(),
    });

    // Limpar o campo de mensagem
    newMessage.value = '';

    nextTick(() => {
      scrollToBottom();
    });
    await loadMessages();
  } catch (error) {
    // Handle error silently
  }
};

// Função para atualizar item
const handleUpdateItem = item => {
  emit('update:item', item);
};

// Função para lidar com item atualizado
const handleItemUpdated = () => {
  emit('item-updated');
};

// Função para lidar com clique na etapa
const handleStageClick = stage => {
  // Não permitir mover para a mesma etapa atual
  if (stage.key === item.value?.funnel_stage) {
    return;
  }

  selectedStageForMove.value = stage;
  showStageMoveModal.value = true;

  // Mostrar toast de confirmação
  emitter.emit('newToastMessage', {
    message: `Preparando para mover para "${stage.name}"`,
    type: 'info',
  });
};

// Função para confirmar movimento da etapa
const handleConfirmStageMove = async () => {
  if (!selectedStageForMove.value || !item.value) {
    return;
  }

  try {
    const response = await KanbanAPI.moveToStage(
      item.value.id,
      selectedStageForMove.value.key,
      item.value.funnel_id
    );

    if (response) {
      // Atualizar o item com os novos dados
      item.value = response;
      emit('update:item', response);

      // Registra a atividade
      await registerActivity('stage_changed', {
        old_stage: item.value.funnel_stage,
        new_stage: selectedStageForMove.value.key,
      });

      // Guardar o nome da etapa antes de limpar
      const stageName = selectedStageForMove.value.name;

      // Fechar modal
      showStageMoveModal.value = false;
      selectedStageForMove.value = null;

      // Mostrar sucesso
      emitter.emit('newToastMessage', {
        message: `Item movido para "${stageName}"`,
        type: 'success',
      });
    }
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: 'Erro ao mover item para a etapa',
      type: 'error',
    });
  }
};

// Adicione antes do setup
const showMoveModal = ref(false);
const moveForm = ref({
  funnel_id: null,
  funnel_stage: null,
});

// Inicializar moveForm quando item for carregado
watch(
  () => item.value,
  newItem => {
    if (newItem) {
      moveForm.value = {
        funnel_id: newItem.funnel_id,
        funnel_stage: newItem.funnel_stage,
      };
    }
  },
  { immediate: true }
);

// Computed para obter as etapas do funil selecionado
const availableStages = computed(() => {
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

// Função para mover o item
const handleMove = async () => {
  try {
    const payload = {
      ...(item.value || {}),
      funnel_id: moveForm.value.funnel_id,
      funnel_stage: moveForm.value.funnel_stage,
    };

    const { data } = await KanbanAPI.updateItem(item.value?.id, payload);
    emit('update:item', data);
    showMoveModal.value = false;

    // Registra a atividade
    await registerActivity('stage_changed', {
      old_stage: item.value?.funnel_stage,
      new_stage: moveForm.value.funnel_stage,
    });
  } catch (error) {
    // Handle error silently
  }
};

// Função para duplicar o item
const handleDuplicateItem = async () => {
  try {
    const duplicatedItem = {
      ...(item.value || {}),
      id: undefined,
      item_details: {
        ...(item.value?.item_details || {}),
        title: `${item.value?.item_details?.title || 'Item'} (Cópia)`,
      },
    };

    const { data } = await KanbanAPI.createItem(duplicatedItem);
    emitter.emit('newToastMessage', {
      message: 'Item duplicado com sucesso',
      action: { type: 'success' },
    });
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: 'Erro ao duplicar o item',
      action: { type: 'error' },
    });
  }
};

// Remove mockMessages
const messages = ref([]);
const isLoadingMessages = ref(false);

const loadMessages = async () => {
  const accountId = store.getters.getCurrentAccountId;
  if (!item.value?.item_details?.conversation?.id || !accountId) {
    return;
  }

  try {
    isLoadingMessages.value = true;
    const response = await messageAPI.getPreviousMessages({
      accountId,
      conversationId: item.value?.conversation.id,
      before: Math.floor(Date.now() / 1000),
    });

    messages.value = response.data.payload
      .filter(msg => msg.message_type === 1)
      .map(msg => ({
        id: msg.id,
        text: msg.content,
        isMe: msg.sender?.id === currentUser.value?.id,
        timestamp: new Date(Number(msg.created_at) * 1000).toLocaleTimeString(
          'pt-BR',
          {
            hour: '2-digit',
            minute: '2-digit',
          }
        ),
        sender: msg.sender,
      }));

    nextTick(() => {
      scrollToBottom();
    });
  } catch (error) {
    // Handle error silently
  } finally {
    isLoadingMessages.value = false;
  }
};

const scrollToBottom = () => {
  const chatContainer = document.querySelector('.chat-messages');
  if (chatContainer) {
    chatContainer.scrollTop = chatContainer.scrollHeight;
  }
};

// Adiciona watch para recarregar mensagens quando a conversa mudar
watch(
  () => item.value?.item_details?.conversation?.id,
  newId => {
    if (newId) {
      loadMessages();
    }
  }
);

// Garante que as mensagens sejam carregadas quando o item for carregado
watch(
  () => item.value,
  newItem => {
    if (newItem) {
      loadMessages();
    }
  },
  { immediate: true }
);

const funnels = computed(() => store.getters['funnel/getFunnels'] || []);

// Opcional: resetar etapa ao trocar de funil
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

// Preview das seleções ativas
const selectedLinksPreview = computed(() => {
  const links = [];
  if (selectedItemId.value) {
    links.push({ type: 'item', id: selectedItemId.value });
  }
  if (selectedConversationId.value) {
    links.push({ type: 'conversation', id: selectedConversationId.value });
  }
  if (selectedContactId.value) {
    links.push({ type: 'contact', id: selectedContactId.value });
  }
  return links;
});

// Attachments serão gerenciados pelas abas individuais

// Função para remover anexo
const removeAttachment = async attachmentId => {
  try {
    // Implementar lógica para remover anexo
    // Aqui você pode implementar a lógica de remoção
  } catch (error) {
    // Handle error silently
  }
};
</script>

<template>
  <div class="kanban-details flex flex-col gap-6">
    <!-- Header with Edit Button -->
    <div
      v-if="!isLoading && item && showHeader"
      class="flex items-center justify-between pb-4 border-b border-slate-200 dark:border-slate-700"
    >
      <div class="flex items-center gap-3">
        <h2 class="text-lg font-semibold text-slate-900 dark:text-slate-100">
          {{ item?.item_details?.title || t('KANBAN.ITEM_DETAILS') }}
        </h2>
        <!-- Status Badge -->
        <span
          v-if="item?.item_details?.status"
          class="px-2.5 py-1 text-xs font-medium rounded-full"
          :class="{
            'bg-green-50 text-green-700 dark:bg-green-900 dark:text-green-300':
              item.item_details.status === 'won',
            'bg-red-50 text-red-700 dark:bg-red-900 dark:text-red-300':
              item.item_details.status === 'lost',
          }"
        >
          {{
            item.item_details.status === 'won'
              ? 'Ganho'
              : item.item_details.status === 'lost'
                ? 'Perdido'
                : item.item_details.status
          }}
        </span>
        <!-- Priority Badge -->
        <span
          v-if="priorityInfo"
          class="px-2.5 py-1 text-xs font-medium rounded-full"
          :class="priorityInfo.class"
        >
          {{ priorityInfo.label }}
        </span>
      </div>

      <!-- Edit Button -->
      <button
        v-if="showEditButton"
        class="flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-700 dark:text-slate-300 bg-slate-100 dark:bg-slate-800 hover:bg-slate-200 dark:hover:bg-slate-700 rounded-lg transition-colors"
        @click="$emit('edit')"
      >
        <fluent-icon icon="edit" size="16" />
        {{ t('KANBAN.FORM.EDIT_ITEM') || 'Editar' }}
      </button>
    </div>

    <!-- Loading State -->
    <div v-if="isLoading" class="flex-1 flex justify-center items-center py-12">
      <span
        class="w-8 h-8 border-2 border-t-woot-500 border-r-woot-500 border-b-transparent border-l-transparent rounded-full animate-spin"
      />
    </div>

    <!-- Error State -->
    <div
      v-else-if="error"
      class="flex-1 flex justify-center items-center py-12"
    >
      <div class="text-center">
        <p class="text-red-500 mb-4">Erro ao carregar detalhes do item</p>
        <button
          class="px-4 py-2 bg-woot-500 text-white rounded"
          @click="fetchItemDetails"
        >
          Tentar novamente
        </button>
      </div>
    </div>

    <!-- Content -->
    <div v-else-if="item">
      <!-- Indicador de Progresso nas Etapas -->
      <div v-if="stageProgress.stages.length > 0" class="w-full p-4">
        <div
          class="bg-white dark:bg-slate-800 rounded-xl p-6 border border-slate-100 dark:border-slate-700 shadow-sm stage-progress-container"
        >
          <!-- Header com progresso geral -->
          <div
            class="flex items-center justify-between mb-4 stage-progress-header"
          >
            <div class="flex items-center gap-2">
              <div class="w-2 h-2 bg-woot-500 rounded-full animate-pulse" />
              <span
                class="text-sm font-semibold text-slate-900 dark:text-slate-100"
              >
                {{ t('KANBAN.STAGE.FUNNEL_PROGRESS') }}
              </span>
            </div>
            <div class="flex items-center gap-2">
              <span
                class="text-xs text-slate-500 bg-slate-100 dark:bg-slate-700 px-3 py-1 rounded-full font-medium"
              >
                {{ stageProgress.currentStageIndex + 1 }} de
                {{ stageProgress.stages.length }}
              </span>
              <span
                class="text-xs text-slate-600 dark:text-slate-400 font-medium"
              >
                {{
                  Math.round(
                    (stageProgress.currentStageIndex /
                      Math.max(stageProgress.stages.length - 1, 1)) *
                      100
                  )
                }}%
              </span>
            </div>
          </div>

          <!-- Barra de progresso principal -->
          <div class="relative mb-6">
            <div
              class="w-full bg-slate-200 dark:bg-slate-700 rounded-full h-2 overflow-hidden stage-progress-bar"
            >
              <div
                class="h-full bg-gradient-to-r from-woot-500 via-woot-500 to-woot-600 rounded-full transition-all duration-1000 ease-out"
                :style="{
                  width:
                    stageProgress.currentStageIndex > 0
                      ? `${(stageProgress.currentStageIndex / Math.max(stageProgress.stages.length - 1, 1)) * 100}%`
                      : '0%',
                }"
              />
            </div>
          </div>

          <!-- Etapas detalhadas -->
          <div class="relative">
            <!-- Linha de conexão sutil -->
            <div class="absolute top-6 left-6 right-6 h-px stage-connector" />

            <!-- Container das etapas -->
            <div class="flex justify-between relative">
              <!-- Tooltips dos agentes (desktop) -->
              <div
                v-for="transition in stageProgress.stageTransitions"
                :key="transition.key"
                class="absolute top-0 flex flex-col items-center justify-center hidden lg:flex"
                :style="{
                  left: `calc(1.5rem + ${((transition.fromIndex + (transition.toIndex - transition.fromIndex) / 2) / Math.max(stageProgress.stages.length - 1, 1)) * 100}%)`,
                  transform: 'translateX(-50%) translateY(-100%)',
                }"
              >
                <div
                  class="bg-slate-900 dark:bg-slate-100 text-white dark:text-slate-900 rounded-lg px-3 py-2 shadow-lg mb-2 max-w-32 stage-tooltip"
                >
                  <div class="text-center">
                    <span class="text-xs font-semibold block">
                      {{ transition.user?.name || 'Sistema' }}
                    </span>
                    <span class="text-xs opacity-75 block">
                      {{ formatDate(transition.created_at) }}
                    </span>
                  </div>
                  <!-- Seta do tooltip -->
                  <div
                    class="absolute top-full left-1/2 transform -translate-x-1/2 w-0 h-0 border-l-4 border-r-4 border-t-4 border-transparent border-t-slate-900 dark:border-t-slate-100"
                  />
                </div>
              </div>

              <div
                v-for="(stage, index) in stageProgress.stages"
                :key="stage.key"
                class="flex flex-col items-center group cursor-pointer relative"
                @click="handleStageClick(stage)"
              >
                <!-- Círculo da etapa com melhor design -->
                <div
                  class="relative flex items-center justify-center w-12 h-12 rounded-full stage-circle z-10 border-2"
                  :class="{
                    // Etapa atual - destaque especial
                    'current bg-woot-500 border-woot-400 text-white shadow-xl shadow-woot-500/30 ring-4 ring-woot-500/20':
                      index === stageProgress.currentStageIndex,
                    // Etapas completadas - sucesso
                    'bg-green-500 border-green-400 text-white shadow-lg shadow-green-500/25':
                      index < stageProgress.currentStageIndex &&
                      stageProgress.completedStages.includes(stage.key),
                    // Etapas visitadas mas não completadas - atenção
                    'bg-amber-400 border-amber-300 text-white shadow-lg shadow-amber-400/25':
                      stageProgress.visitedStages.includes(stage.key) &&
                      index < stageProgress.currentStageIndex &&
                      !stageProgress.completedStages.includes(stage.key),
                    // Etapas futuras - neutro
                    'bg-slate-100 dark:bg-slate-700 border-slate-300 dark:border-slate-600 text-slate-400 dark:text-slate-500':
                      index > stageProgress.currentStageIndex,
                    // Etapas anteriores não visitadas - erro sutil
                    'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800 text-red-400 dark:text-red-500':
                      index < stageProgress.currentStageIndex &&
                      !stageProgress.visitedStages.includes(stage.key),
                  }"
                >
                  <!-- Ícones baseados no status -->
                  <span
                    v-if="
                      index < stageProgress.currentStageIndex &&
                      stageProgress.completedStages.includes(stage.key)
                    "
                    class="text-sm font-bold"
                  >
                    ✓
                  </span>
                  <span
                    v-else-if="
                      stageProgress.visitedStages.includes(stage.key) &&
                      index < stageProgress.currentStageIndex &&
                      !stageProgress.completedStages.includes(stage.key)
                    "
                    class="text-sm font-bold"
                  >
                    ↺
                  </span>
                  <span
                    v-else-if="
                      index < stageProgress.currentStageIndex &&
                      !stageProgress.visitedStages.includes(stage.key)
                    "
                    class="text-sm font-bold"
                  >
                    ✗
                  </span>
                  <span v-else class="text-sm font-semibold">
                    {{ index + 1 }}
                  </span>

                  <!-- Animação de pulso para etapa atual -->
                  <div
                    v-if="index === stageProgress.currentStageIndex"
                    class="absolute inset-0 rounded-full bg-woot-500 animate-ping opacity-20"
                  />
                </div>

                <!-- Nome da etapa -->
                <div class="mt-3 text-center max-w-20">
                  <div
                    class="text-xs font-semibold transition-colors duration-200 leading-tight"
                    :class="{
                      'text-woot-600 dark:text-woot-400':
                        index === stageProgress.currentStageIndex,
                      'text-green-600 dark:text-green-400':
                        index < stageProgress.currentStageIndex &&
                        stageProgress.completedStages.includes(stage.key),
                      'text-amber-600 dark:text-amber-400':
                        stageProgress.visitedStages.includes(stage.key) &&
                        index < stageProgress.currentStageIndex &&
                        !stageProgress.completedStages.includes(stage.key),
                      'text-slate-500 dark:text-slate-400':
                        index > stageProgress.currentStageIndex,
                      'text-red-500 dark:text-red-400':
                        index < stageProgress.currentStageIndex &&
                        !stageProgress.visitedStages.includes(stage.key),
                    }"
                  >
                    {{ stage.name }}
                  </div>

                  <!-- Badge do estágio atual -->
                  <div
                    v-if="index === stageProgress.currentStageIndex"
                    class="mt-2"
                  >
                    <span
                      class="inline-flex items-center px-2 py-1 rounded-full text-xs font-bold bg-woot-100 dark:bg-woot-900/50 text-woot-700 dark:text-woot-300 border border-woot-200 dark:border-woot-800"
                    >
                      <div
                        class="w-1.5 h-1.5 bg-woot-500 rounded-full mr-1.5 animate-pulse"
                      />
                      Atual
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Legenda (mobile) -->
          <div
            class="mt-6 pt-4 border-t border-slate-200 dark:border-slate-700 lg:hidden"
          >
            <div class="flex flex-wrap justify-center gap-4 text-xs">
              <div class="flex items-center gap-1">
                <div
                  class="w-3 h-3 bg-woot-500 rounded-full border border-woot-400"
                />
                <span class="text-slate-600 dark:text-slate-400">Atual</span>
              </div>
              <div class="flex items-center gap-1">
                <div
                  class="w-3 h-3 bg-green-500 rounded-full border border-green-400"
                />
                <span class="text-slate-600 dark:text-slate-400">Concluída</span>
              </div>
              <div class="flex items-center gap-1">
                <div
                  class="w-3 h-3 bg-amber-400 rounded-full border border-amber-300"
                />
                <span class="text-slate-600 dark:text-slate-400">Visitada</span>
              </div>
              <div class="flex items-center gap-1">
                <div
                  class="w-3 h-3 bg-slate-100 dark:bg-slate-700 rounded-full border border-slate-300 dark:border-slate-600"
                />
                <span class="text-slate-600 dark:text-slate-400">Pendente</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Container das colunas esquerda, meio e direita -->
      <div class="flex flex-col lg:flex-row gap-4">
        <!-- Coluna Esquerda - Dados Básicos do Item -->
        <div class="w-full lg:w-1/4 p-4">
          <KanbanBasicDataPanel
            :item="item"
            :conversation-data="item?.conversation"
            :loading-conversation="false"
            :current-stage-name="currentStageName"
            :item-description="itemDescription"
            @navigate-to-conversation="navigateToConversation"
            @context-menu="handleContextMenu"
            @stage-click="handleStageClick"
            @close="$emit('close')"
          />
        </div>

        <!-- Coluna do Meio - Tabs e Informações -->
        <div class="w-full lg:w-1/2 p-4">
          <!-- Conteúdo das Tabs -->
          <KanbanTabs
            :item="item"
            :is-stacklab="isStacklab"
            :kanban-items="kanbanItems"
            :conversations="conversations"
            :contacts-list="contactsList"
            :loading-items="loadingItems"
            :loading-conversations="loadingConversations"
            :loading-contacts="loadingContacts"
            :current-user="currentUser"
            :agent-list="agentList"
            @upload-attachment="handleNoteAttachment"
            @delete-attachment="removeAttachment"
            @update-item="handleUpdateItem"
            @item-updated="handleItemUpdated"
            @navigate-to-conversation="navigateToConversation"
            @context-menu="handleContextMenu"
            @stage-click="handleStageClick"
            @tab-changed="currentActiveTab = $event"
          />
        </div>

        <!-- Coluna Direita - Ações e Informações -->
        <div class="w-full lg:w-1/4 p-4 space-y-6">
          <!-- Seção de Agente Responsável -->
          <KanbanAgentInfo
            :item="item"
            :agent-info="agentInfo"
            :loading-agent="loadingAgent"
          />

          <!-- Seção de Ofertas -->
          <div
            v-if="
              item?.item_details?.offers && item.item_details.offers.length > 0
            "
            class="offers-section -mt-6"
          >
            <div class="flex items-center justify-between mb-2">
              <div class="flex items-center gap-1.5">
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
                  class="lucide lucide-users-round-icon lucide-users-round text-slate-600 dark:text-slate-400"
                >
                  <line x1="12" x2="12" y1="2" y2="22" />
                  <path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
                </svg>
                <span class="text-xs text-slate-700 dark:text-slate-300">
                  {{ t('KANBAN.OFFERS.TITLE') || 'Ofertas' }}
                </span>
              </div>
            </div>

            <div class="offers-content">
              <div class="space-y-2">
                <div
                  v-for="offer in item.item_details.offers"
                  :key="offer.id || offer.name"
                  class="flex items-center gap-2 p-2 bg-white dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700"
                >
                  <div
                    class="w-8 h-8 bg-blue-100 dark:bg-blue-900 rounded-full flex items-center justify-center flex-shrink-0"
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
                      class="text-blue-600 dark:text-blue-400"
                    >
                      <line x1="12" x2="12" y1="2" y2="22" />
                      <path
                        d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"
                      />
                    </svg>
                  </div>
                  <div class="flex-1 min-w-0">
                    <div
                      class="font-medium text-sm text-slate-900 dark:text-slate-100 truncate"
                    >
                      {{ offer.description || 'Oferta' }}
                    </div>
                  </div>
                  <div v-if="offer.value" class="text-right flex-shrink-0">
                    <div
                      class="font-semibold text-sm text-slate-900 dark:text-slate-100"
                    >
                      {{ formatCurrencyForOffer(offer.value, offer.currency) }}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Seção de Atividades -->
          <div class="activities-section">
            <KanbanActivitiesTab :item="item" :is-stacklab="isStacklab" />
          </div>

          <!-- Seção de Conversa Vinculada -->
          <div
            v-if="conversationInfo && currentActiveTab !== 'basic_data'"
            class="conversation-section"
          >
            <div class="flex items-center justify-between gap-1 mb-2">
              <div class="flex items-center gap-1">
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
                  class="text-slate-600 dark:text-slate-400 flex-shrink-0"
                >
                  <path
                    d="M12 3H4a2 2 0 0 0-2 2v16.286a.71.71 0 0 0 1.212.502l2.202-2.202A2 2 0 0 1 6.828 19H20a2 2 0 0 0 2-2v-4"
                  />
                  <path d="M16 3h6v6" />
                  <path d="m16 9 6-6" />
                </svg>
                <span class="text-xs text-slate-700 dark:text-slate-300">
                  {{ t('KANBAN.FORM.CONVERSATION.LABEL') }}
                </span>
              </div>
              <span class="text-xs text-slate-600 dark:text-slate-400">
                Clique para navegar
              </span>
            </div>
            <div
              class="bg-white dark:bg-slate-800 rounded-lg border border-slate-200/30 dark:border-slate-700/30 p-3 cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-700/50 transition-colors"
              @click="
                navigateToConversation($event, conversationInfo.display_id)
              "
              @contextmenu="handleContextMenu($event, conversationInfo.id)"
            >
              <!-- Contato -->
              <div
                v-if="conversationInfo.contact"
                class="flex items-center gap-3 mb-2"
              >
                <img
                  v-if="conversationInfo.contact.thumbnail"
                  :src="conversationInfo.contact.thumbnail"
                  :alt="conversationInfo.contact.name"
                  class="w-8 h-8 rounded-full object-cover"
                />
                <div
                  v-else
                  class="w-8 h-8 bg-slate-200 dark:bg-slate-600 rounded-full flex items-center justify-center"
                >
                  <span
                    class="text-xs font-medium text-slate-600 dark:text-slate-400"
                  >
                    {{
                      conversationInfo.contact.name?.charAt(0)?.toUpperCase() ||
                      '?'
                    }}
                  </span>
                </div>
                <div class="flex-1">
                  <div class="flex items-center justify-between">
                    <div
                      class="font-semibold text-sm text-slate-900 dark:text-slate-100"
                    >
                      <span
                        class="text-xs text-slate-500 dark:text-slate-400 mr-1"
                        >#{{ conversationInfo.display_id }}</span>
                      {{
                        conversationInfo.contact.name ||
                        t('KANBAN.CONTACT_UNKNOWN')
                      }}
                    </div>
                    <!-- Informações à direita: telefone, inbox e tipo -->
                    <div class="flex items-center gap-3">
                      <!-- Phone number do contato -->
                      <div
                        v-if="conversationInfo.contact?.phone_number"
                        class="flex items-center gap-1 text-xs text-slate-600 dark:text-slate-400"
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
                          class="text-slate-500 dark:text-slate-400"
                        >
                          <path
                            d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"
                          />
                        </svg>
                        {{ conversationInfo.contact.phone_number }}
                      </div>
                      <!-- Inbox info -->
                      <div
                        v-if="conversationInfo.inbox"
                        class="flex items-center gap-1"
                      >
                        <span
                          class="text-xs font-medium text-slate-600 dark:text-slate-400"
                          >{{ conversationInfo.inbox.name }}</span>
                        <span
                          class="px-1.5 py-0.5 bg-slate-100 dark:bg-slate-700 rounded text-xs text-slate-700 dark:text-slate-300"
                        >
                          {{
                            conversationInfo.inbox.channel_type?.replace(
                              'Channel::',
                              ''
                            ) || 'Web'
                          }}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="flex items-center gap-1">
                  <!-- Status -->
                  <span
                    class="text-xs px-2 py-0.5 rounded-full font-medium"
                    :class="{
                      'bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300':
                        conversationInfo.status === 'open',
                      'bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300':
                        conversationInfo.status === 'pending',
                      'bg-slate-100 text-slate-700 dark:bg-slate-700 dark:text-slate-300':
                        conversationInfo.status === 'resolved',
                    }"
                  >
                    {{ conversationInfo.status }}
                  </span>
                  <!-- Unread count -->
                  <span
                    v-if="conversationInfo.unread_count > 0"
                    class="flex items-center justify-center h-5 min-w-[1rem] px-1.5 text-xs font-medium bg-red-500 text-white rounded-full shadow-sm"
                  >
                    {{
                      conversationInfo.unread_count > 9
                        ? '9+'
                        : conversationInfo.unread_count
                    }}
                  </span>
                </div>
              </div>

              <!-- Informações adicionais -->
              <div
                class="flex flex-wrap gap-3 text-xs text-slate-600 dark:text-slate-400 mb-2"
              >
                <!-- Última atividade -->
                <div
                  v-if="conversationInfo.last_activity_at"
                  class="flex items-center gap-1"
                >
                  <span class="font-medium">{{ t('KANBAN.LAST_ACTIVITY') }}:</span>
                  <span>{{
                    formatDate(conversationInfo.last_activity_at)
                  }}</span>
                </div>
              </div>

              <!-- Labels -->
              <div
                v-if="
                  conversationInfo.label_list &&
                  conversationInfo.label_list.length > 0
                "
                class="flex flex-wrap gap-1"
              >
                <span
                  v-for="label in conversationInfo.label_list"
                  :key="label"
                  class="text-xs px-2 py-0.5 bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300 rounded-full"
                >
                  {{ label }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Modal de Mover -->
  <Modal
    v-if="showMoveModal"
    :show="showMoveModal"
    @close="showMoveModal = false"
  >
    <div class="p-4 space-y-4">
      <h3 class="text-lg font-medium text-slate-900 dark:text-slate-100">
        {{ t('KANBAN.BULK_ACTIONS.MOVE.TITLE') }}
      </h3>

      <!-- Seletor de Funil -->
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
          <option v-for="funnel in funnels" :key="funnel.id" :value="funnel.id">
            {{ funnel.name }}
          </option>
        </select>
      </div>

      <!-- Seletor de Etapa -->
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
            v-for="stage in availableStages"
            :key="stage.id"
            :value="stage.id"
          >
            {{ stage.name }}
          </option>
        </select>
      </div>

      <!-- Botões -->
      <div class="flex justify-end gap-2 mt-4">
        <button
          class="px-4 py-2 text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
          @click="showMoveModal = false"
        >
          {{ t('KANBAN.CANCEL') }}
        </button>
        <button
          class="px-4 py-2 text-sm text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors"
          @click="handleMove"
        >
          {{ t('KANBAN.MOVE') }}
        </button>
      </div>
    </div>
  </Modal>

  <!-- Modal de Mensagem Rápida -->
  <Modal
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
          :conversation-id="
            conversationInfo?.id || item.value?.item_details?.conversation_id
          "
          :current-stage="item.value?.funnel_stage || ''"
          :contact="
            conversationInfo?.contact ||
            item.value?.item_details?.conversation?.contact
          "
          :conversation="
            conversationInfo || item.value?.item_details?.conversation
          "
          :item="item.value"
          @close="() => (showSendMessageModal = false)"
          @send="handleSendMessage"
        />
      </div>
    </div>
  </Modal>

  <!-- Modal de Confirmação de Movimento de Etapa -->
  <Modal
    v-if="showStageMoveModal"
    :show="showStageMoveModal"
    @close="showStageMoveModal = false"
  >
    <div class="p-4 space-y-4">
      <h3 class="text-lg font-medium text-slate-900 dark:text-slate-100">
        {{ t('KANBAN.MOVE_STAGE_CONFIRMATION.TITLE') || 'Confirmar Movimento' }}
      </h3>

      <div class="space-y-3">
        <p class="text-sm text-slate-600 dark:text-slate-400">
          {{
            t('KANBAN.MOVE_STAGE_CONFIRMATION.MESSAGE') ||
            'Tem certeza que deseja mover este item para a etapa:'
          }}
        </p>

        <div
          v-if="selectedStageForMove"
          class="p-3 bg-slate-50 dark:bg-slate-800 rounded-lg border"
        >
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded-full bg-slate-400" />
            <span class="font-medium text-slate-900 dark:text-slate-100">
              {{ selectedStageForMove.name }}
            </span>
          </div>
        </div>
      </div>

      <!-- Botões -->
      <div class="flex justify-end gap-2 mt-6">
        <button
          class="px-4 py-2 text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
          @click="showStageMoveModal = false"
        >
          {{ t('KANBAN.CANCEL') }}
        </button>
        <button
          class="px-4 py-2 text-sm text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors"
          @click="handleConfirmStageMove"
        >
          {{ t('KANBAN.MOVE_STAGE_CONFIRMATION.CONFIRM') || 'Mover' }}
        </button>
      </div>
    </div>
  </Modal>
</template>

<style scoped>
.kanban-details {
  max-height: 90vh;
  overflow-y: auto;
  -ms-overflow-style: none; /* IE and Edge */
  scrollbar-width: none; /* Firefox */
}

.kanban-details::-webkit-scrollbar {
  display: none;
}

.conversation-section {
  margin-bottom: 1.5rem;
}

.offers-section {
  background-color: white;
  border: 1px solid #e2e8f0;
  border-radius: 0.5rem;
  padding: 0.75rem;
}

.dark .offers-section {
  background-color: #1e293b;
  border-color: #334155;
}

.activities-section {
  background-color: white;
  border: 1px solid #e2e8f0;
  border-radius: 0.5rem;
  padding: 0.75rem;
}

.dark .activities-section {
  background-color: #1e293b;
  border-color: #334155;
}

.offers-content {
  gap: 0.5rem;
  display: flex;
  flex-direction: column;
}

/* Mobile: Layout responsivo otimizado */
@media (max-width: 1023px) {
  .kanban-details {
    flex-direction: column;
  }

  /* Em mobile, as colunas se empilham verticalmente */
  .kanban-details .flex.flex-col.lg\\:flex-row {
    flex-direction: column;
  }
}

/* Animações do componente de progresso */
@keyframes progress-shine {
  0% {
    transform: translateX(-100%);
  }
  100% {
    transform: translateX(100%);
  }
}

@keyframes stage-pulse {
  0%,
  100% {
    transform: scale(1);
    opacity: 0.8;
  }
  50% {
    transform: scale(1.05);
    opacity: 1;
  }
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

/* Estilos para o indicador de progresso */
.stage-progress-container {
  animation: fade-in-up 0.6s ease-out;
}

.stage-progress-header {
  animation: fade-in-up 0.4s ease-out;
}

.stage-progress-bar {
  position: relative;
  overflow: hidden;
}

.stage-circle {
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  position: relative;
}

.stage-circle:hover {
  transform: scale(1.1) translateY(-2px);
}

.stage-circle.current {
  animation: stage-pulse 2s infinite;
}

.stage-tooltip {
  animation: fade-in-up 0.3s ease-out;
  backdrop-filter: blur(8px);
}

.stage-connector {
  background: linear-gradient(
    90deg,
    rgba(148, 163, 184, 0.3),
    rgba(148, 163, 184, 0.6),
    rgba(148, 163, 184, 0.3)
  );
}

/* Dark mode adjustments */
.dark .stage-connector {
  background: linear-gradient(
    90deg,
    rgba(71, 85, 105, 0.3),
    rgba(71, 85, 105, 0.6),
    rgba(71, 85, 105, 0.3)
  );
}

/* Responsive adjustments */
@media (max-width: 768px) {
  .stage-progress-container {
    padding: 1rem;
  }

  .stage-circle {
    width: 2.5rem;
    height: 2.5rem;
  }

  .stage-circle span {
    font-size: 0.75rem;
  }
}
</style>
