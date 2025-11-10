<script setup>
import { ref, watchEffect, computed, watch, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import FunnelSelector from './FunnelSelector.vue';
import { emitter } from 'shared/helpers/mitt';
import { useConfig } from 'dashboard/composables/useConfig';
import conversationAPI from '../../../../api/inbox/conversation';
import funnelAPI from '../../../../api/funnel';
import offersAPI from '../../../../api/offers';
import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';

// Modificar a função toLocalISOString para retornar o formato exato
const toLocalISOString = (date, includeTime = true) => {
  if (!date) return null;
  try {
    // Ajuste para corrigir o problema do fuso horário
    let d = new Date(date);

    // Verificar se é apenas data (sem hora) para evitar problemas de fuso horário
    if (typeof date === 'string' && date.length === 10) {
      // Para datas sem hora, forçar hora 12:00 para evitar problemas de fuso
      const parts = date.split('-');
      // Importante: mês em JavaScript é baseado em zero (0-11)
      d = new Date(parts[0], parts[1] - 1, parts[2], 12, 0, 0);
    }

    // Obter ano, mês e dia de forma segura considerando fuso horário local
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');

    if (!includeTime) {
      return `${year}-${month}-${day}`;
    }

    const hours = String(d.getHours()).padStart(2, '0');
    const minutes = String(d.getMinutes()).padStart(2, '0');

    // Retornar no formato exato para datetime-local: YYYY-MM-DDThh:mm
    return `${year}-${month}-${day}T${hours}:${minutes}`;
  } catch (error) {
    return null;
  }
};

// Função para extrair IDs dos agentes do formato completo
const extractAgentIds = (assignedAgents) => {
  if (!assignedAgents || !Array.isArray(assignedAgents)) return [];
  
  // Se é array de objetos completos (formato do JSON), extrair apenas os IDs
  if (assignedAgents.length > 0 && typeof assignedAgents[0] === 'object' && assignedAgents[0].id) {
    return assignedAgents.map(agent => agent.id);
  }
  
  // Se já é array de IDs, retornar como está
  return assignedAgents;
};

const { t } = useI18n();
const store = useStore();
const emit = defineEmits(['saved', 'close']);
const activeTab = ref('general');

// Computed para tipos de campos traduzidos
const getFieldTypeLabel = (type) => {
  const typeMap = {
    string: t('KANBAN.FORM.CUSTOM_FIELDS.TYPE_TEXT'),
    number: t('KANBAN.FORM.CUSTOM_FIELDS.TYPE_NUMBER'),
    date: t('KANBAN.FORM.CUSTOM_FIELDS.TYPE_DATE'),
    boolean: t('KANBAN.FORM.CUSTOM_FIELDS.TYPE_BOOLEAN'),
  };
  return typeMap[type] || type;
};

const props = defineProps({
  funnelId: {
    type: [String, Number],
    required: true,
  },
  stage: {
    type: String,
    required: true,
  },
  position: {
    type: Number,
    default: 0,
  },
  initialData: {
    type: Object,
    default: null,
  },
  isEditing: {
    type: Boolean,
    default: false,
  },
  currentConversation: {
    type: Object,
    default: null,
  },
  initialDate: {
    type: Date,
    default: null,
  },
});

const loading = ref(false);
const loadingAgents = ref(false);
const selectedFunnel = computed(
  () => store.getters['funnel/getSelectedFunnel']
);

// Refs para controle do dropdown de agentes
const agentSearch = ref('');
const agentDropdownOpen = ref(false);
const agentSelectorRef = ref(null);
const filteredAgents = computed(() => {
  if (!agentSearch.value)
    return store.getters['agents/getAgents'].filter(
      a => !form.value.assigned_agents.some(sel => sel === a.id)
    );
  return store.getters['agents/getAgents'].filter(
    a =>
      !form.value.assigned_agents.some(sel => sel === a.id) &&
      a.name.toLowerCase().includes(agentSearch.value.toLowerCase())
  );
});

// Computed para obter as etapas do funil selecionado
const availableStages = computed(() => {
  if (!selectedFunnel.value?.stages) return [];

  return Object.entries(selectedFunnel.value.stages)
    .map(([id, stage]) => ({
      id,
      name: stage.name,
      position: stage.position,
    }))
    .sort((a, b) => a.position - b.position);
});

// Refs para controle da conversa
const showConversationInput = ref(
  !!props.initialData?.item_details?.conversation_id
);
const conversations = ref([]);
const loadingConversations = ref(false);

// Refs para controle das ofertas
const availableOffers = ref([]);
const loadingOffers = ref(false);
const showOffersInput = ref(!!props.initialData?.item_details?.offers?.length);
const showManualOfferForm = ref(false);
const manualOffer = ref({
  description: '',
  value: null,
  currency: { symbol: 'R$', code: 'BRL', locale: 'pt-BR' }
});
// Busca e filtro de conversas
const conversationSearch = ref('');
const conversationDropdownOpen = ref(false);
const conversationSelectorRef = ref(null);
const conversationDropdownStyle = ref({
  top: '0px',
  left: '0px',
  width: '100%',
});
const filteredConversations = computed(() => {
  if (!conversationSearch.value) return conversations.value;
  return conversations.value.filter(c => {
    const sender = c.meta?.sender;
    const text = `${c.id} ${sender?.name || ''} ${
      sender?.email || ''
    }`.toLowerCase();
    return text.includes(conversationSearch.value.toLowerCase());
  });
});
const selectedConversation = computed(() => {
  return (
    conversations.value.find(
      c => c.id === form.value.item_details.conversation_id
    ) || null
  );
});

// Atualizar a função para verificar se tem agendamento
const hasScheduling = computed(() => {
  return !!(
    props.initialData?.item_details?.scheduled_at ||
    props.initialData?.item_details?.deadline_at ||
    props.initialDate
  );
});

// Atualizar a ref showScheduling para usar o computed
const showScheduling = ref(hasScheduling.value);

// Forçar showScheduling a ser true se houver agendamento
// Isso garante que o checkbox esteja marcado
if (hasScheduling.value) {
  showScheduling.value = true;
}

// Atualizar o schedulingType para usar o tipo correto do item
const schedulingType = ref(
  props.initialData?.item_details?.scheduling_type ||
    (props.initialData?.item_details?.scheduled_at ? 'schedule' : 'deadline')
);


// Atualizar o form.value para incluir as ofertas e datas
const form = ref({
  title: props.initialData?.title || '',
  description:
    props.initialData?.item_details?.description ||
    props.initialData?.description ||
    '',
  funnel_id: props.funnelId,
  funnel_stage: props.stage,
  position: props.position,
  assigned_agents: extractAgentIds(props.initialData?.assigned_agents) || [],
  item_details: {
    title: props.initialData?.title || '',
    description:
      props.initialData?.item_details?.description ||
      props.initialData?.description ||
      '',
    value: null,
    offers: [],
    priority:
      props.initialData?.item_details?.priority ||
      props.initialData?.priority ||
      'none',
    conversation_id: props.initialData?.item_details?.conversation_id || null,
    scheduling_type: schedulingType.value,
    scheduled_at: null,
    deadline_at: null,
  },
  custom_attributes: props.initialData?.item_details?.custom_attributes || [],
});


// Adicione estas refs
const customAttributes = ref(
  Array.isArray(props.initialData?.item_details?.custom_attributes)
    ? props.initialData.item_details.custom_attributes.map(attr => ({
        name: attr.name || '',
        type: attr.type || '',
      }))
    : Array.isArray(props.initialData?.custom_attributes)
    ? props.initialData.custom_attributes.map(attr => ({
        name: attr.name || '',
        type: attr.type || '',
      }))
    : []
);

// Campos globais do funil
const globalCustomAttributes = ref([]);
const globalCustomAttributesValues = ref({});

// Adicionar um watch para atualizar customAttributes ao trocar de item para edição
watch(
  () => [
    props.initialData?.item_details?.custom_attributes,
    props.initialData?.custom_attributes,
  ],
  ([newItemDetailsAttrs, newRootAttrs]) => {
    if (Array.isArray(newItemDetailsAttrs)) {
      customAttributes.value = newItemDetailsAttrs.map(attr => ({
        name: attr.name || '',
        type: attr.type || '',
      }));
    } else if (Array.isArray(newRootAttrs)) {
      customAttributes.value = newRootAttrs.map(attr => ({
        name: attr.name || '',
        type: attr.type || '',
      }));
    } else {
      customAttributes.value = [];
    }
  },
  { immediate: true, deep: true }
);

// Modifique o onMounted para remover a busca de agentes
onMounted(async () => {
  // Carregar agentes do store
  loadingAgents.value = true;
  try {
    await store.dispatch('agents/get');
    
    // Selecionar automaticamente o usuário atual ao criar novo item
    if (!props.isEditing && form.value.assigned_agents.length === 0) {
      const currentUser = store.getters.getCurrentUser;
      if (currentUser?.id) {
        form.value.assigned_agents.push(currentUser.id);
      }
    }
  } catch (error) {
    // Error handling
  } finally {
    loadingAgents.value = false;
  }

  // Se tiver conversa atual ou estiver editando, buscar conversas
  if (
    props.currentConversation ||
    (props.isEditing && props.initialData?.item_details?.conversation_id)
  ) {
    showConversationInput.value = true;
    fetchConversations();
  }

  // Buscar ofertas disponíveis
  fetchOffers();

  // Carregar campos globais do funil se estiver editando
  if (props.isEditing && props.initialData?.funnel_id) {
    loadGlobalAttributesForFunnel(props.initialData.funnel_id);
  }

  // Adicione este onMounted para gerenciar o clique fora do dropdown
  const handleClickOutside = event => {
    if (
      showCurrencySelector.value &&
      !event.target.closest('.currency-selector')
    ) {
      showCurrencySelector.value = false;
    }
  };

  document.addEventListener('mousedown', handleClickOutside);
  onUnmounted(() => {
    document.removeEventListener('mousedown', handleClickOutside);
  });

  // Processar ofertas existentes ao carregar o formulário em modo de edição
  if (props.isEditing && props.initialData?.item_details?.offers?.length) {
    form.value.item_details.offers = [...props.initialData.item_details.offers];
  }

  // Sincronizar valores de agendamento
  if (hasScheduling.value) {
    showScheduling.value = true;

    if (props.initialData?.item_details?.scheduled_at) {
      schedulingType.value = 'schedule';
      form.value.item_details.scheduled_at = toLocalISOString(
        props.initialData.item_details.scheduled_at
      );
    } else if (props.initialData?.item_details?.deadline_at) {
      schedulingType.value = 'deadline';
      form.value.item_details.deadline_at = toLocalISOString(
        props.initialData.item_details.deadline_at,
        false // Apenas data para prazo
      );
    } else if (props.initialDate) {
      // Se houver uma data inicial, configure como prazo
      schedulingType.value = 'deadline';
      form.value.item_details.deadline_at = toLocalISOString(
        props.initialDate,
        false // Apenas data para prazo
      );
    }
  }
});

// Adicionar watch para o campo showScheduling
watch(showScheduling, newValue => {
  if (!newValue) {
    // Se o checkbox foi desmarcado, limpe os campos de agendamento
    form.value.item_details.scheduled_at = null;
    form.value.item_details.deadline_at = null;
  } else {
    // Se foi marcado mas não há tipo definido, defina um padrão
    if (!form.value.item_details.scheduling_type) {
      schedulingType.value = 'deadline';
      form.value.item_details.scheduling_type = 'deadline';
    }
  }
});

// Atualizar o watch do schedulingType
watch(schedulingType, (newType, oldType) => {
  if (newType === oldType) return;

  form.value.item_details.scheduling_type = newType;

  if (newType === 'deadline') {
    // Se mudar para deadline, preserva a data existente ou converte do scheduled_at
    if (
      !form.value.item_details.deadline_at &&
      form.value.item_details.scheduled_at
    ) {
      // Converter para o formato de date
      form.value.item_details.deadline_at = toLocalISOString(
        form.value.item_details.scheduled_at,
        false // Sem hora
      );
    }
    form.value.item_details.scheduled_at = null;
  } else {
    // Se mudar para schedule, preserva a data existente ou converte do deadline_at
    if (
      !form.value.item_details.scheduled_at &&
      form.value.item_details.deadline_at
    ) {
      // Converter para o formato de datetime-local
      const deadlineDate = new Date(form.value.item_details.deadline_at);
      // Define hora como meio-dia por padrão
      deadlineDate.setHours(12, 0, 0, 0);
      form.value.item_details.scheduled_at = toLocalISOString(deadlineDate);
    }
    form.value.item_details.deadline_at = null;
  }
});

// Função para buscar conversas
const fetchConversations = async () => {
  try {
    loadingConversations.value = true;
    // Se estiver editando ou tiver conversa atual, usa ela
    if (props.currentConversation) {
      conversations.value = [props.currentConversation];
    } else {
      // Usa a API diretamente para buscar conversas
      const response = await conversationAPI.get({});
      conversations.value = response.data.data.payload;
    }
  } catch (error) {
    // Error handling
  } finally {
    loadingConversations.value = false;
  }
};

// Função para buscar ofertas disponíveis
const fetchOffers = async () => {
  try {
    loadingOffers.value = true;
    const response = await offersAPI.getOffers();
    availableOffers.value = (response.data || []).map(offer => ({
      id: offer.id,
      name: offer.title,
      discount_percentage: offer.value,
      currency: offer.currency,
      type: offer.type,
      created_at: offer.created_at,
      image_url: offer.image_url
    }));
  } catch (error) {
    console.error('Erro ao carregar ofertas:', error);
    availableOffers.value = [];
  } finally {
    loadingOffers.value = false;
  }
};

// Função para carregar atributos globais de um funil específico
const loadGlobalAttributesForFunnel = async (funnelId) => {
  try {
    const response = await funnelAPI.get();
    const funnels = response.data || [];
    const selectedFunnelData = funnels.find(f => f.id === funnelId);

    // Inicializar campos globais do funil
    if (selectedFunnelData?.global_custom_attributes?.length > 0) {
      globalCustomAttributes.value = [...selectedFunnelData.global_custom_attributes];

      // Buscar valores existentes dos custom_attributes (que é um array)
      const existingCustomAttrs = props.initialData?.item_details?.custom_attributes || [];

      // Inicializar valores dos campos globais com dados existentes
      const existingGlobalValues = {};
      selectedFunnelData.global_custom_attributes.forEach(attr => {
        // Buscar o valor atual deste campo no array de custom_attributes
        const existingAttr = Array.isArray(existingCustomAttrs)
          ? existingCustomAttrs.find(ca => ca.name === attr.name)
          : null;

        if (existingAttr) {
          // Usar o valor existente
          existingGlobalValues[attr.name] = existingAttr.value;
        } else if (attr.is_list) {
          // Para campos de lista novos, inicializar como array com um item vazio
          existingGlobalValues[attr.name] = [''];
        } else {
          // Para campos simples novos, inicializar vazio
          existingGlobalValues[attr.name] = '';
        }
      });
      globalCustomAttributesValues.value = existingGlobalValues;
    } else {
      globalCustomAttributes.value = [];
      globalCustomAttributesValues.value = {};
    }
  } catch (error) {
    console.error('Erro ao carregar atributos globais do funil:', error);
    globalCustomAttributes.value = [];
    globalCustomAttributesValues.value = {};
  }
};


watch(showConversationInput, newValue => {
  if (!newValue) {
    form.value.item_details.conversation_id = null;
  } else {
    fetchConversations();
  }
});

watch(showOffersInput, newValue => {
  if (!newValue) {
    form.value.item_details.offers = [];
    form.value.item_details.value = null;
  }
});

// Funções para gerenciar ofertas
const isOfferSelected = (offerId) => {
  return form.value.item_details.offers.some(offer => {
    // Verificar se a oferta tem ID e corresponde
    if (offer.id) {
      return offer.id === offerId;
    }
    // Para ofertas vindas da API que podem ter offer_id
    if (offer.offer_id) {
      return offer.offer_id === offerId;
    }
    return false;
  });
};

const toggleOfferSelection = (offer) => {
  const offerIndex = form.value.item_details.offers.findIndex(o => {
    // Verificar correspondência por ID ou offer_id
    if (o.id) return o.id === offer.id;
    if (o.offer_id) return o.offer_id === offer.id;
    return false;
  });

  if (offerIndex !== -1) {
    // Remover oferta
    form.value.item_details.offers.splice(offerIndex, 1);
  } else {
    // Adicionar oferta
    form.value.item_details.offers.push({
      id: offer.id, // Preservar o ID da oferta
      description: offer.name,
      value: offer.discount_percentage,
      currency: {
        symbol: offer.currency === 'BRL' ? 'R$' : offer.currency === 'USD' ? '$' : '€',
        code: offer.currency,
        locale: offer.currency === 'BRL' ? 'pt-BR' : offer.currency === 'USD' ? 'en-US' : 'de-DE'
      }
    });
  }

  // Atualizar o valor principal (primeira oferta)
  if (form.value.item_details.offers.length > 0) {
    const firstOffer = form.value.item_details.offers[0];
    form.value.item_details.value = firstOffer.value;
  } else {
    form.value.item_details.value = null;
  }
};

const addManualOffer = () => {
  if (!manualOffer.value.description || !manualOffer.value.value) {
    emitter.emit('newToastMessage', {
      message: 'Preencha descrição e valor da oferta',
      type: 'error',
    });
    return;
  }

  form.value.item_details.offers.push({
    manual: true, // Marcar como oferta manual
    description: manualOffer.value.description,
    value: parseFloat(manualOffer.value.value),
    currency: manualOffer.value.currency
  });

  // Atualizar o valor principal (primeira oferta)
  if (form.value.item_details.offers.length > 0) {
    const firstOffer = form.value.item_details.offers[0];
    form.value.item_details.value = firstOffer.value;
  }

  // Resetar o formulário
  manualOffer.value = {
    description: '',
    value: null,
    currency: { symbol: 'R$', code: 'BRL', locale: 'pt-BR' }
  };
  showManualOfferForm.value = false;

  emitter.emit('newToastMessage', {
    message: 'Oferta adicionada com sucesso',
    type: 'success',
  });
};

const cancelManualOffer = () => {
  manualOffer.value = {
    description: '',
    value: null,
    currency: { symbol: 'R$', code: 'BRL', locale: 'pt-BR' }
  };
  showManualOfferForm.value = false;
};

const removeOffer = (index) => {
  form.value.item_details.offers.splice(index, 1);
  
  // Atualizar o valor principal
  if (form.value.item_details.offers.length > 0) {
    const firstOffer = form.value.item_details.offers[0];
    form.value.item_details.value = firstOffer.value;
  } else {
    form.value.item_details.value = null;
  }
};

// Atualiza o form quando o funil ou etapa mudar
watchEffect(() => {
  form.value = {
    ...form.value,
    funnel_id: selectedFunnel.value?.id || props.funnelId,
    funnel_stage: form.value.funnel_stage || props.stage,
    position: props.position,
    assigned_agents:
      form.value.assigned_agents || extractAgentIds(props.initialData?.assigned_agents) || [],
    title:
      form.value.title ||
      props.initialData?.title ||
      props.initialData?.item_details?.title ||
      '',
    item_details: {
      ...form.value.item_details,
      title:
        form.value.title ||
        props.initialData?.title ||
        props.initialData?.item_details?.title ||
        '',
      description: form.value.description,
      priority:
        form.value.item_details.priority ||
        props.initialData?.item_details?.priority ||
        props.initialData?.priority ||
        'none',
      value:
        form.value.item_details.value || props.initialData?.item_details?.value,
      currency:
        form.value.item_details.currency ||
        props.initialData?.item_details?.currency,
      scheduled_at:
        form.value.item_details.scheduled_at ||
        props.initialData?.item_details?.scheduled_at,
      deadline_at:
        form.value.item_details.deadline_at ||
        props.initialData?.item_details?.deadline_at,
    },
  };
});

// Adicionar watch para sincronizar o título em tempo real
watch(
  () => form.value.title,
  newTitle => {
    if (form.value.item_details) {
      form.value.item_details.title = newTitle;
    }
  }
);

// Adicionar watch para sincronizar a descrição em tempo real
watch(
  () => form.value.description,
  newDescription => {
    if (form.value.item_details) {
      form.value.item_details.description = newDescription;
    }
  }
);

// Adicionar watch para sincronizar assigned_agents quando initialData mudar
watch(
  () => props.initialData?.assigned_agents,
  newAssignedAgents => {
    if (Array.isArray(newAssignedAgents)) {
      form.value.assigned_agents = extractAgentIds(newAssignedAgents);
    }
  },
  { immediate: true, deep: true }
);

// Watch para sincronizar ofertas ao abrir para edição
watch(
  () => props.initialData?.item_details?.offers,
  (newOffers) => {
    if (props.isEditing && newOffers?.length) {
      if (form.value.item_details.offers.length === 0) {
        form.value.item_details.offers = [...newOffers];
      }
      // Marcar o checkbox se houver ofertas
      if (!showOffersInput.value) {
        showOffersInput.value = true;
      }
    }
  },
  { immediate: true, deep: true }
);

// Adicionar watch para atualizar valores globais quando o funil mudar
watch(
  () => selectedFunnel.value?.id,
  async (newFunnelId) => {
    // Só atualizar se não estiver editando (quando editando, usamos o funnel_id do item)
    if (newFunnelId && activeTab.value === 'custom_fields' && !props.isEditing) {
      try {
        const response = await funnelAPI.get();
        const funnels = response.data || [];
        const selectedFunnelData = funnels.find(f => f.id === newFunnelId);

        // Atualizar campos globais quando o funil mudar
        if (selectedFunnelData?.global_custom_attributes?.length > 0) {
          globalCustomAttributes.value = [...selectedFunnelData.global_custom_attributes];

          // Preservar valores existentes ou inicializar vazios
          const existingGlobalValues = { ...globalCustomAttributesValues.value };
          selectedFunnelData.global_custom_attributes.forEach(attr => {
            if (!(attr.name in existingGlobalValues)) {
              if (attr.is_list) {
                existingGlobalValues[attr.name] = [''];
              } else {
                existingGlobalValues[attr.name] = '';
              }
            }
          });
          globalCustomAttributesValues.value = existingGlobalValues;
        } else {
          globalCustomAttributes.value = [];
          globalCustomAttributesValues.value = {};
        }
      } catch (error) {
        console.error('Erro ao atualizar campos globais:', error);
      }
    }
  },
  { immediate: true }
);

// Modificar a função validateForm para incluir a validação de data
const validateForm = () => {
  const errors = {};

  if (!form.value.title?.trim()) {
    errors.title = t('KANBAN.ERRORS.TITLE_REQUIRED');
  }

  if (!form.value.funnel_id) {
    errors.funnel_id = t('KANBAN.ERRORS.FUNNEL_REQUIRED');
  }

  if (!form.value.funnel_stage) {
    errors.funnel_stage = t('KANBAN.ERRORS.STAGE_REQUIRED');
  }

  // Removidas todas as validações de data/prazo

  if (Object.keys(errors).length > 0) {
    emitter.emit('newToastMessage', {
      message: errors[Object.keys(errors)[0]],
      type: 'error',
    });
    return errors;
  }

  return null;
};

const priorityOptions = [
  { id: 'none', name: t('KANBAN.PRIORITY_LABELS.NONE') },
  { id: 'low', name: t('KANBAN.PRIORITY_LABELS.LOW') },
  { id: 'medium', name: t('KANBAN.PRIORITY_LABELS.MEDIUM') },
  { id: 'high', name: t('KANBAN.PRIORITY_LABELS.HIGH') },
  { id: 'urgent', name: t('KANBAN.PRIORITY_LABELS.URGENT') },
];

// Função para obter estilos de prioridade com cores hexadecimais
const getPriorityStyle = (optionId) => {
  const isSelected = optionId === form.value.item_details.priority;
  
  const styles = {
    none: {
      selected: {
        borderColor: '#e2e8f0',
        backgroundColor: '#f1f5f9',
        color: '#475569',
      },
      unselected: {
        borderColor: '#e2e8f0',
        backgroundColor: '#f1f5f9',
        color: '#64748b',
      },
    },
    urgent: {
      selected: {
        borderColor: '#fecdd3',
        backgroundColor: '#e11d48',
        color: '#ffffff',
      },
      unselected: {
        borderColor: '#fecdd3',
        backgroundColor: '#ffe4e6',
        color: '#e11d48',
      },
    },
    high: {
      selected: {
        borderColor: '#fed7aa',
        backgroundColor: '#ea580c',
        color: '#ffffff',
      },
      unselected: {
        borderColor: '#fed7aa',
        backgroundColor: '#ffedd5',
        color: '#ea580c',
      },
    },
    medium: {
      selected: {
        borderColor: '#fef08a',
        backgroundColor: '#eab308',
        color: '#ffffff',
      },
      unselected: {
        borderColor: '#fef08a',
        backgroundColor: '#fef9c3',
        color: '#996b00',
      },
    },
    low: {
      selected: {
        borderColor: '#bbf7d0',
        backgroundColor: '#22c55e',
        color: '#ffffff',
      },
      unselected: {
        borderColor: '#bbf7d0',
        backgroundColor: '#dcfce7',
        color: '#16a34a',
      },
    },
  };
  
  const styleConfig = styles[optionId]?.[isSelected ? 'selected' : 'unselected'] || styles.none.unselected;
  
  return {
    borderColor: styleConfig.borderColor,
    backgroundColor: styleConfig.backgroundColor,
    color: styleConfig.color,
  };
};

// Função auxiliar para registrar atividades
const registerActivity = async (itemId, type, details) => {
  try {
    await store.dispatch('kanban/registerActivity', {
      itemId,
      type,
      details,
    });
  } catch (error) {
    // Error handling
  }
};

// Modificar handleSubmit para não usar agentsList
const handleSubmit = async e => {
  e.preventDefault();
  const errors = validateForm();
  if (errors) return;

  try {
    loading.value = true;

    // Garantir que título e descrição estejam sincronizados
    form.value.item_details.title = form.value.title;
    form.value.item_details.description = form.value.description;

    let finalItemDetails = {};

    // Se estiver editando, preservar os dados originais do item
    if (props.isEditing && props.initialData?.item_details) {
      finalItemDetails = JSON.parse(
        JSON.stringify(props.initialData.item_details)
      );

      const fieldsToPreserve = [
        'notes',
        'checklist',
        'attachments',
        'activities',
      ];
      fieldsToPreserve.forEach(field => {
        if (props.initialData.item_details[field]) {
          finalItemDetails[field] = props.initialData.item_details[field];
        }
      });
    }

    const fieldsToUpdate = [
      'title',
      'description',
      'value',
      'currency',
      'priority',
      'conversation_id',
      'scheduling_type',
      'scheduled_at',
      'deadline_at',
      'custom_attributes',
    ];

    fieldsToUpdate.forEach(field => {
      if (form.value.item_details[field] !== undefined) {
        finalItemDetails[field] = form.value.item_details[field];
      }
    });

    finalItemDetails.title = form.value.title;
    finalItemDetails.offers = form.value.item_details.offers;

    if (form.value.item_details.offers.length > 0) {
      finalItemDetails.value = form.value.item_details.offers[0].value;
      finalItemDetails.currency = form.value.item_details.offers[0].currency;
    }

    // Criar o payload completo
    const payload = {
      funnel_id: selectedFunnel.value?.id || props.funnelId,
      funnel_stage: form.value.funnel_stage,
      position: props.position,
      assigned_agents: form.value.assigned_agents,
      item_details: finalItemDetails,
      conversation_display_id: form.value.conversation_display_id,
    };

    // custom_attributes deve ser um array de objetos {name, type, value}
    const existingCustomAttributes = Array.isArray(finalItemDetails.custom_attributes)
      ? finalItemDetails.custom_attributes
      : [];

    // Atualizar custom_attributes com os valores globais preenchidos
    const updatedCustomAttributes = existingCustomAttributes.map(attr => {
      // Se o campo global foi preenchido, atualizar seu valor
      if (globalCustomAttributesValues.value[attr.name] !== undefined) {
        const newValue = globalCustomAttributesValues.value[attr.name];
        
        // Filtrar arrays vazios
        if (Array.isArray(newValue)) {
          const filteredArray = newValue.filter(v => v !== null && v !== undefined && v !== '');
          return { ...attr, value: filteredArray };
        }
        
        // Para valores simples
        return { ...attr, value: newValue };
      }
      
      // Manter o atributo sem alteração
      return attr;
    });

    finalItemDetails.custom_attributes = updatedCustomAttributes;

    const result = props.isEditing
      ? await store.dispatch('kanban/updateItemDetails', {
          itemId: props.initialData.id,
          details: payload, // Enviar o payload completo com funnel_stage
        })
      : await store.dispatch('kanban/createKanbanItem', payload);

    emitter.emit('newToastMessage', {
      message: props.isEditing
        ? 'Item atualizado com sucesso'
        : 'Item criado com sucesso',
      type: 'success',
    });

    emit('saved', result);
    emit('close');
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: 'Erro ao salvar item',
      type: 'error',
    });
  } finally {
    loading.value = false;
  }
};



// Adicione esta função no script
const formatCurrencyValue = (value, currency) => {
  if (!value) return '-';

  try {
    return new Intl.NumberFormat(currency.locale, {
      style: 'currency',
      currency: currency.code,
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(value);
  } catch (error) {
    return value.toString();
  }
};


const { isStacklab } = useConfig();

// Função para copiar o ID do item
const copyItemId = async () => {
  if (!props.initialData?.id) return;

  try {
    await navigator.clipboard.writeText(props.initialData.id.toString());
    emitter.emit('newToastMessage', {
      message: t('KANBAN.ITEM_ID_COPIED') || 'ID do item copiado!',
      type: 'success',
    });
  } catch (error) {
    // Fallback para browsers antigos
    const textArea = document.createElement('textarea');
    textArea.value = props.initialData.id.toString();
    document.body.appendChild(textArea);
    textArea.select();
    document.execCommand('copy');
    document.body.removeChild(textArea);

    emitter.emit('newToastMessage', {
      message: t('KANBAN.ITEM_ID_COPIED') || 'ID do item copiado!',
      type: 'success',
    });
  }
};

// Funções para gerenciar agentes
const addAgent = (agent) => {
  if (!form.value.assigned_agents.some(a => a === agent.id))
    form.value.assigned_agents.push(agent.id);
  agentDropdownOpen.value = false;
  agentSearch.value = '';
};

const removeAgent = (agentId) => {
  form.value.assigned_agents = form.value.assigned_agents.filter(
    a => a !== agentId
  );
};

// Funções para gerenciar campos globais de lista
const addGlobalListItem = (fieldName) => {
  if (!globalCustomAttributesValues.value[fieldName]) {
    globalCustomAttributesValues.value[fieldName] = [];
  }
  globalCustomAttributesValues.value[fieldName].push('');
};

const removeGlobalListItem = (fieldName, index) => {
  if (globalCustomAttributesValues.value[fieldName] &&
      globalCustomAttributesValues.value[fieldName].length > 1) {
    globalCustomAttributesValues.value[fieldName].splice(index, 1);
  }
};

const getAgentById = (agentId) => {
  return store.getters['agents/getAgents'].find(a => a.id === agentId);
};

const openAgentDropdown = () => {
  agentDropdownOpen.value = true;
  agentSearch.value = '';
};

const closeAgentDropdown = (e) => {
  if (!agentSelectorRef.value?.contains(e.target)) {
    agentDropdownOpen.value = false;
  }
};

const addCustomAttribute = () => {
  customAttributes.value.push({ name: '', type: '' });
};

function removeCustomAttribute(index) {
  customAttributes.value.splice(index, 1);
}

// No script, garanta que customAttributes sempre seja um array e, se vazio, adicione pelo menos um campo ao entrar na aba:
watch(activeTab, async tab => {
  if (tab === 'custom_fields') {
    // Fazer get para buscar dados do funnel quando abrir a aba de dados adicionais
    try {
      const response = await funnelAPI.get();
      const funnels = response.data || [];

      // Identificar o funil correto: usar o funnel_id do item original se estiver editando, senão usar o selectedFunnel
      const currentFunnelId = props.isEditing
        ? (props.initialData?.funnel_id || props.funnelId)
        : (selectedFunnel.value?.id || props.funnelId);

      // Encontrar o funil correto
      const selectedFunnelData = funnels.find(f => f.id === currentFunnelId);

      // Inicializar campos globais do funil
      if (selectedFunnelData?.global_custom_attributes?.length > 0) {
        globalCustomAttributes.value = [...selectedFunnelData.global_custom_attributes];

        // Buscar valores existentes dos custom_attributes (que é um array)
        const existingCustomAttrs = props.initialData?.item_details?.custom_attributes || [];
        
        // Inicializar valores dos campos globais com dados existentes
        const existingGlobalValues = {};
        selectedFunnelData.global_custom_attributes.forEach(attr => {
          // Buscar o valor atual deste campo no array de custom_attributes
          const existingAttr = Array.isArray(existingCustomAttrs)
            ? existingCustomAttrs.find(ca => ca.name === attr.name)
            : null;

          if (existingAttr) {
            // Usar o valor existente
            existingGlobalValues[attr.name] = existingAttr.value;
          } else if (attr.is_list) {
            // Para campos de lista novos, inicializar como array com um item vazio
            existingGlobalValues[attr.name] = [''];
          } else {
            // Para campos simples novos, inicializar vazio
            existingGlobalValues[attr.name] = '';
          }
        });
        globalCustomAttributesValues.value = existingGlobalValues;
      } else {
        globalCustomAttributes.value = [];
        globalCustomAttributesValues.value = {};
      }

      // Inicializar customAttributes apenas com campos adicionais (não globais)
      if (customAttributes.value.length === 0) {
        customAttributes.value.push({ name: '', type: '' });
      }
    } catch (error) {
      console.error('Erro ao buscar dados do funnel:', error);
      // Fallback para comportamento anterior se a API falhar
      if (customAttributes.value.length === 0) {
        customAttributes.value.push({ name: '', type: '' });
      }
    }
  }
});

function openConversationDropdown() {
  conversationDropdownOpen.value = true;
  conversationSearch.value = '';
  setTimeout(() => {
    const selector = conversationSelectorRef.value;
    if (selector) {
      const rect = selector.getBoundingClientRect();
      conversationDropdownStyle.value = {
        position: 'fixed',
        top: `${rect.bottom + window.scrollY}px`,
        left: `${rect.left + window.scrollX}px`,
        width: `${rect.width}px`,
        zIndex: 99999,
      };
    }
    const input = selector?.querySelector('input');
    if (input) input.focus();
  }, 0);
}
function selectConversation(id) {
  form.value.item_details.conversation_id = id;
  form.value.conversation_display_id = id;
  conversationDropdownOpen.value = false;
}
function closeConversationDropdown(e) {
  if (!conversationSelectorRef.value?.contains(e.target)) {
    conversationDropdownOpen.value = false;
  }
}
onMounted(() => {
  document.addEventListener('mousedown', closeConversationDropdown);
  document.addEventListener('mousedown', closeAgentDropdown);
});
onUnmounted(() => {
  document.removeEventListener('mousedown', closeConversationDropdown);
  document.removeEventListener('mousedown', closeAgentDropdown);
});
</script>

<template>
  <form
    class="flex flex-col gap-4 max-h-[85vh] overflow-y-auto w-full px-4"
    @submit.prevent="handleSubmit"
  >
    <!-- Tabs -->
    <div class="tabs-container">
      <div class="tabs-scroll-wrapper">
        <button
          type="button"
          class="tab-button flex-shrink-0"
          :class="[activeTab === 'general' ? 'tab-active' : 'tab-inactive']"
          @click="activeTab = 'general'"
        >
          <div class="flex items-center gap-2">
            <fluent-icon icon="document" size="16" />
            {{ t('KANBAN.TABS.GENERAL') }}
          </div>
        </button>

        <button
          type="button"
          class="tab-button flex-shrink-0"
          :class="[activeTab === 'pipeline' ? 'tab-active' : 'tab-inactive']"
          @click="activeTab = 'pipeline'"
        >
          <div class="flex items-center gap-2">
            <fluent-icon icon="task" size="16" />
            {{ t('KANBAN.TABS.PIPELINE') }}
          </div>
        </button>

        <button
          type="button"
          class="tab-button flex-shrink-0"
          :class="[activeTab === 'assignment' ? 'tab-active' : 'tab-inactive']"
          @click="activeTab = 'assignment'"
        >
          <div class="flex items-center gap-2">
            <fluent-icon icon="bot" size="16" />
            {{ t('KANBAN.TABS.ASSIGNMENT') }}
          </div>
        </button>

        <button
          v-if="isStacklab === true"
          type="button"
          class="tab-button flex-shrink-0"
          :class="[activeTab === 'scheduling' ? 'tab-active' : 'tab-inactive']"
          @click="activeTab = 'scheduling'"
        >
          <div class="flex items-center gap-2">
            <fluent-icon icon="calendar-clock" size="16" />
            {{ t('KANBAN.TABS.SCHEDULING') }}
          </div>
        </button>

        <button
          type="button"
          class="tab-button flex-shrink-0"
          :class="[
            activeTab === 'relationships' ? 'tab-active' : 'tab-inactive',
          ]"
          @click="activeTab = 'relationships'"
        >
          <div class="flex items-center gap-2">
            <fluent-icon icon="attach" size="16" />
            {{ t('KANBAN.TABS.RELATIONSHIPS') }}
          </div>
        </button>

        <button
          type="button"
          class="tab-button flex-shrink-0"
          :class="activeTab === 'custom_fields' ? 'tab-active' : 'tab-inactive'"
          @click.prevent.stop="activeTab = 'custom_fields'"
        >
          {{ t('KANBAN.TABS.CUSTOM_FIELDS') }}
        </button>
      </div>
    </div>

    <!-- Conteúdo das Tabs -->
    <div
      class="bg-white dark:bg-slate-800 p-4 rounded-xl border border-slate-200 dark:border-slate-700 shadow-sm"
    >
      <!-- Tab Dados Gerais -->
      <div v-if="activeTab === 'general'" class="space-y-6">
        <div class="flex items-center justify-between mb-6">
          <div class="flex items-center gap-3">
            <div
              class="flex items-center justify-center w-8 h-8 rounded-lg bg-woot-50 dark:bg-woot-900/20"
            >
              <fluent-icon icon="document" size="18" class="text-woot-500" />
            </div>
            <h4 class="text-base font-medium text-slate-800 dark:text-slate-100">
              {{ t('KANBAN.TABS.GENERAL') }}
            </h4>
          </div>

          <!-- Item ID Badge and Copy Button -->
          <div v-if="isEditing && initialData?.id" class="flex items-center gap-2">
            <span class="px-2 py-1 text-xs font-medium bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-300 rounded-full">
              ID: {{ initialData.id }}
            </span>
            <button
              type="button"
              class="p-1.5 rounded-md bg-slate-100 dark:bg-slate-800 hover:bg-slate-200 dark:hover:bg-slate-700 text-slate-600 dark:text-slate-400 transition-colors"
              @click="copyItemId"
              :title="t('KANBAN.COPY_ITEM_ID')"
            >
              <fluent-icon icon="copy" size="14" />
            </button>
          </div>
        </div>

        <!-- Título -->
        <div class="space-y-2">
          <label
            class="block text-sm font-medium text-slate-700 dark:text-slate-300"
          >
            {{ t('KANBAN.FORM.TITLE.LABEL') }}
          </label>
          <input
            v-model="form.title"
            type="text"
            class="w-full px-4 py-3 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500 shadow-sm"
            :placeholder="t('KANBAN.FORM.TITLE.PLACEHOLDER')"
            required
          />
        </div>

        <!-- Grid com Valor e Descrição -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <!-- Ofertas - Ocupa 1/3 -->
          <div class="lg:col-span-1">
            <div
              class="bg-gradient-to-br from-woot-50/50 to-white dark:from-slate-800/50 dark:to-slate-800 rounded-lg border border-woot-100 dark:border-slate-700 overflow-hidden"
            >
              <!-- Header do Card -->
              <div
                class="p-4 border-b border-woot-100/50 dark:border-slate-700/50"
              >
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-4">
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                    >
                      {{ t('KANBAN.FORM.OFFERS.LABEL') }}
                    </span>
                  </div>
                  <div class="flex items-center gap-2">
                    <input
                      id="has-offers"
                      v-model="showOffersInput"
                      type="checkbox"
                      class="w-4 h-4 text-woot-500 border-slate-300 rounded focus:ring-woot-500"
                    />
                    <label
                      for="has-offers"
                      class="text-xs text-slate-600 dark:text-slate-400"
                    >
                      {{ t('KANBAN.FORM.OFFERS.HAS_OFFERS') }}
                    </label>
                  </div>
                </div>
              </div>

              <!-- Conteúdo do Card -->
              <div
                v-if="showOffersInput"
                class="divide-y divide-slate-100 dark:divide-slate-700/50 max-h-96 overflow-y-auto"
              >
                <!-- Loading State -->
                <div v-if="loadingOffers" class="flex justify-center items-center py-8">
                  <span class="loading-spinner" />
                </div>

                <!-- Empty State -->
                <div
                  v-else-if="!availableOffers.length"
                  class="flex flex-col items-center justify-center py-8 text-slate-600"
                >
                  <fluent-icon icon="tag" size="32" class="mb-2 text-slate-400" />
                  <p class="text-sm text-center">
                    Nenhuma oferta encontrada
                  </p>
                  <p class="text-xs text-center mt-1 text-slate-500">
                    Crie ofertas na seção de ofertas
                  </p>
                </div>

                <!-- Lista de Ofertas Disponíveis -->
                <div v-else class="p-4 space-y-3">
                  <div
                    v-for="offer in availableOffers"
                    :key="offer.id"
                    class="offer-card bg-white dark:bg-slate-800 rounded-lg shadow-sm border overflow-hidden cursor-pointer transition-all hover:shadow-md"
                    :class="{
                      'border-woot-300 dark:border-woot-600 ring-2 ring-woot-200 dark:ring-woot-800': isOfferSelected(offer.id),
                      'border-slate-200 dark:border-slate-700': !isOfferSelected(offer.id)
                    }"
                    @click="toggleOfferSelection(offer)"
                  >
                    <div class="flex items-center gap-3">
                      <!-- Checkbox de Seleção -->
                      <div class="flex items-center p-3">
                        <input
                          type="checkbox"
                          :checked="isOfferSelected(offer.id)"
                          class="w-4 h-4 text-woot-500 border-slate-300 rounded focus:ring-woot-500"
                          @click.stop
                          @change="toggleOfferSelection(offer)"
                        />
                      </div>

                      <!-- Imagem da Oferta ou Placeholder -->
                      <div class="w-20 h-20 flex-shrink-0 rounded-lg overflow-hidden bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-800 dark:to-slate-900 flex items-center justify-center">
                        <img
                          v-if="offer.image_url"
                          :src="offer.image_url"
                          :alt="offer.name"
                          class="w-full h-full object-cover"
                        />
                        <fluent-icon v-else icon="image" size="32" class="text-slate-300 dark:text-slate-700" />
                      </div>

                      <!-- Informações da Oferta -->
                      <div class="flex-1 min-w-0 py-3 pr-3">
                        <div class="flex items-center gap-2 mb-1.5">
                          <span class="inline-block px-1.5 py-0.5 text-xs font-medium text-slate-500 dark:text-slate-400 bg-slate-100 dark:bg-slate-700 rounded">
                            #{{ offer.id }}
                          </span>
                          <span
                            v-if="offer.type"
                            :class="[
                              'inline-block px-1.5 py-0.5 text-xs font-medium rounded',
                              offer.type === 'service' 
                                ? 'bg-blue-100 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300' 
                                : 'bg-purple-100 dark:bg-purple-900/20 text-purple-700 dark:text-purple-300'
                            ]"
                          >
                            {{ offer.type === 'service' ? t('KANBAN.FORM.OFFERS.TYPE_SERVICE') : t('KANBAN.FORM.OFFERS.TYPE_PRODUCT') }}
                          </span>
                        </div>
                        <h4 class="text-sm font-semibold text-slate-900 dark:text-white mb-2 truncate">
                          {{ offer.name }}
                        </h4>

                        <!-- Valor e moeda -->
                        <div class="inline-flex items-center gap-1.5 px-2 py-0.5 bg-green-50 dark:bg-green-900/20 rounded">
                          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-green-600 dark:text-green-400">
                            <circle cx="12" cy="12" r="10"/>
                            <path d="M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8"/>
                            <path d="M12 18V6"/>
                          </svg>
                          <span class="text-xs font-bold text-green-700 dark:text-green-300">
                            {{ offer.discount_percentage }} {{ offer.currency }}
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Botão para Adicionar Oferta Manual (sempre visível) -->
                <div v-if="!loadingOffers" class="p-4">
                  <button
                    v-if="!showManualOfferForm"
                    type="button"
                    @click="showManualOfferForm = true"
                    class="w-full flex items-center justify-center gap-2 px-4 py-3 bg-white dark:bg-slate-800 border-2 border-dashed border-slate-300 dark:border-slate-600 rounded-lg text-sm text-slate-600 dark:text-slate-400 hover:border-woot-500 hover:text-woot-500 dark:hover:border-woot-500 dark:hover:text-woot-400 transition-colors"
                  >
                    <fluent-icon icon="add" size="16" />
                    {{ t('KANBAN.FORM.OFFERS.ADD_MANUAL_OFFER') }}
                  </button>

                  <!-- Formulário de Oferta Manual -->
                  <div
                    v-if="showManualOfferForm"
                    class="bg-white dark:bg-slate-800 rounded-lg border-2 border-woot-300 dark:border-woot-600 p-4 space-y-3"
                  >
                    <div class="flex items-center justify-between mb-2">
                      <h5 class="text-sm font-medium text-slate-700 dark:text-slate-300">
                        {{ t('KANBAN.FORM.OFFERS.NEW_MANUAL_OFFER') }}
                      </h5>
                      <button
                        type="button"
                        @click="cancelManualOffer"
                        class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-300"
                      >
                        <fluent-icon icon="dismiss" size="16" />
                      </button>
                    </div>

                    <div class="space-y-2">
                      <label class="block text-xs text-slate-600 dark:text-slate-400">
                        Descrição
                      </label>
                      <input
                        v-model="manualOffer.description"
                        type="text"
                        class="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
                        placeholder="Ex: Consultoria Premium"
                      />
                    </div>

                    <div class="space-y-2">
                      <div class="grid grid-cols-2 gap-2">
                        <label class="block text-xs text-slate-600 dark:text-slate-400">
                          Valor
                        </label>
                        <label class="block text-xs text-slate-600 dark:text-slate-400">
                          Moeda
                        </label>
                      </div>
                      <div class="grid grid-cols-2 gap-2">
                        <input
                          v-model="manualOffer.value"
                          type="number"
                          step="0.01"
                          class="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
                          placeholder="0.00"
                        />
                        <select
                          v-model="manualOffer.currency.code"
                          @change="
                            manualOffer.currency = {
                              symbol: manualOffer.currency.code === 'BRL' ? 'R$' : manualOffer.currency.code === 'USD' ? '$' : '€',
                              code: manualOffer.currency.code,
                              locale: manualOffer.currency.code === 'BRL' ? 'pt-BR' : manualOffer.currency.code === 'USD' ? 'en-US' : 'de-DE'
                            }
                          "
                          class="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
                        >
                          <option value="BRL">BRL (R$)</option>
                          <option value="USD">USD ($)</option>
                          <option value="EUR">EUR (€)</option>
                        </select>
                      </div>
                    </div>

                    <div class="flex gap-2 pt-2">
                      <button
                        type="button"
                        @click="addManualOffer"
                        class="flex-1 px-3 py-2 bg-woot-500 hover:bg-woot-600 text-white text-sm rounded-lg transition-colors"
                      >
                        Adicionar
                      </button>
                      <button
                        type="button"
                        @click="cancelManualOffer"
                        class="px-3 py-2 bg-slate-100 hover:bg-slate-200 dark:bg-slate-700 dark:hover:bg-slate-600 text-slate-700 dark:text-slate-300 text-sm rounded-lg transition-colors"
                      >
                        Cancelar
                      </button>
                    </div>
                  </div>
                </div>

                <!-- Ofertas Selecionadas -->
                <div v-if="form.item_details.offers.length > 0" class="p-4 bg-slate-50 dark:bg-slate-800/50">
                  <h5 class="text-xs font-medium text-slate-600 dark:text-slate-400 mb-2">
                    Ofertas Selecionadas ({{ form.item_details.offers.length }})
                  </h5>
                  <div class="space-y-2">
                    <div
                      v-for="(selectedOffer, index) in form.item_details.offers"
                      :key="index"
                      class="flex items-center gap-2 p-2 bg-white dark:bg-slate-700 rounded border border-slate-200 dark:border-slate-600"
                    >
                      <fluent-icon 
                        :icon="selectedOffer.manual ? 'edit' : 'checkmark-circle'" 
                        size="16" 
                        :class="selectedOffer.manual ? 'text-blue-500' : 'text-green-500'" 
                        class="flex-shrink-0" 
                      />
                      <span class="text-sm text-slate-700 dark:text-slate-300 truncate flex-1">
                        {{ selectedOffer.description }}
                      </span>
                      <span 
                        v-if="selectedOffer.manual"
                        class="text-xs px-1.5 py-0.5 bg-blue-100 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300 rounded"
                      >
                        Manual
                      </span>
                      <span class="text-xs text-slate-500 dark:text-slate-400">
                        {{ formatCurrencyValue(selectedOffer.value, selectedOffer.currency) }}
                      </span>
                      <button
                        type="button"
                        @click="removeOffer(index)"
                        class="text-ruby-500 hover:text-ruby-600 dark:text-ruby-400 dark:hover:text-ruby-300 transition-colors ml-1"
                        title="Remover oferta"
                      >
                        <fluent-icon icon="dismiss" size="14" />
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Descrição - Ocupa 2/3 -->
          <div class="lg:col-span-2">
            <div
              class="h-full flex flex-col bg-gradient-to-br from-slate-50/50 to-white dark:from-slate-800/50 dark:to-slate-800 rounded-lg border border-slate-200 dark:border-slate-700 overflow-hidden"
            >
              <div
                class="p-4 border-b border-slate-200/50 dark:border-slate-700/50"
              >
                <label
                  class="block text-sm font-medium text-slate-600 dark:text-slate-300"
                >
                  {{ t('KANBAN.FORM.DESCRIPTION.LABEL') }}
                </label>
              </div>
              <div class="flex-1 p-4">
                <Editor
                  v-model="form.description"
                  :placeholder="t('KANBAN.FORM.DESCRIPTION.PLACEHOLDER')"
                  :max-length="1000"
                  :show-character-count="true"
                  :enable-variables="false"
                  :enable-canned-responses="false"
                  :enable-captain-tools="false"
                  :enabled-menu-options="[]"
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Tab Pipeline -->
      <div v-if="activeTab === 'pipeline'" class="space-y-6">
        <div class="grid grid-cols-2 gap-6">
          <!-- Funil -->
          <div class="space-y-2">
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.FORM.FUNNEL.LABEL') }}
            </label>
            <FunnelSelector class="w-full" />
          </div>

          <!-- Etapa -->
          <div class="space-y-2">
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.FORM.STAGE.LABEL') }}
            </label>
            <select
              v-model="form.funnel_stage"
              class="w-full px-4 py-2.5 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
              :disabled="!selectedFunnel?.id"
            >
              <option value="" disabled>
                {{ t('KANBAN.FORM.STAGE.PLACEHOLDER') }}
              </option>
              <option
                v-for="stage in availableStages"
                :key="stage.id"
                :value="stage.id"
              >
                {{ stage.name }}
              </option>
            </select>
          </div>
        </div>
      </div>

      <!-- Tab Atribuição -->
      <div v-if="activeTab === 'assignment'" class="space-y-6">
        <div class="flex items-center gap-3 mb-6">
          <div
            class="flex items-center justify-center w-8 h-8 rounded-lg bg-woot-50 dark:bg-woot-900/20"
          >
            <fluent-icon icon="bot" size="18" class="text-woot-500" />
          </div>
          <h4 class="text-base font-medium text-slate-800 dark:text-slate-100">
            {{ t('KANBAN.TABS.ASSIGNMENT') }}
          </h4>
        </div>

        <div class="space-y-4">
          <div class="space-y-1.5">
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.FORM.PRIORITY.LABEL') }}
            </label>
            <div class="grid grid-cols-5 gap-2">
              <label
                v-for="option in priorityOptions"
                :key="option.id"
                class="relative flex cursor-pointer"
              >
                <input
                  v-model="form.item_details.priority"
                  type="radio"
                  :value="option.id"
                  class="peer sr-only"
                />
                <div
                  class="w-full px-3 py-2 text-xs text-center rounded-lg border transition-colors"
                  :style="getPriorityStyle(option.id)"
                >
                  {{ option.name }}
                </div>
              </label>
            </div>
          </div>

          <!-- Agente -->
          <div class="space-y-1.5">
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.FORM.AGENT.LABEL') }}
            </label>
            <div ref="agentSelectorRef" class="relative">
              <input
                v-model="agentSearch"
                type="text"
                class="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
                :placeholder="t('KANBAN.FORM.AGENT.PLACEHOLDER')"
                :disabled="loadingAgents"
                @focus="openAgentDropdown"
                @input="openAgentDropdown"
              />
              <div
                v-if="loadingAgents"
                class="absolute right-2 top-1/2 transform -translate-y-1/2"
              >
                <span class="loading-spinner" />
              </div>

              <!-- Dropdown de agentes -->
              <div
                v-if="agentDropdownOpen"
                class="absolute left-0 top-full w-full bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-lg max-h-60 overflow-y-auto z-[99999]"
              >
                <div
                  v-for="agent in filteredAgents"
                  :key="agent.id"
                  class="px-3 py-2 hover:bg-woot-50 dark:hover:bg-slate-700 cursor-pointer flex items-center gap-2"
                  @click="addAgent(agent)"
                >
                  <div
                    class="w-6 h-6 rounded-full bg-woot-500 flex items-center justify-center text-white text-xs font-medium"
                  >
                    {{ agent.name.charAt(0).toUpperCase() }}
                  </div>
                  <span class="text-sm">{{ agent.name }}</span>
                </div>
                <div
                  v-if="filteredAgents.length === 0"
                  class="px-3 py-2 text-slate-400 text-sm"
                >
                  Nenhum agente encontrado
                </div>
              </div>
            </div>

            <!-- Listagem dos agentes selecionados -->
            <div v-if="form.assigned_agents.length" class="space-y-1">
              <div
                class="flex items-center justify-between px-2 py-1 bg-slate-50 dark:bg-slate-800 rounded-lg mb-2"
              >
                <span class="text-sm text-slate-600 dark:text-slate-300">
                  {{ form.assigned_agents.length }} agente{{
                    form.assigned_agents.length !== 1 ? 's' : ''
                  }}
                  selecionado{{ form.assigned_agents.length !== 1 ? 's' : '' }}
                </span>
                <button
                  type="button"
                  class="text-xs text-ruby-500 hover:text-ruby-600 dark:text-ruby-400 dark:hover:text-ruby-300"
                  @click="form.assigned_agents = []"
                >
                  Limpar seleção
                </button>
              </div>
              <div
                v-for="agentId in form.assigned_agents"
                :key="agentId"
                class="flex items-center gap-2 px-2 py-1 border border-slate-100 dark:border-slate-800 rounded mb-1"
              >
                <div
                  class="w-6 h-6 rounded-full bg-woot-500 flex items-center justify-center text-white text-xs font-medium"
                >
                  {{
                    getAgentById(agentId)?.name?.charAt(0).toUpperCase() || '?'
                  }}
                </div>
                <span class="text-sm">{{
                  getAgentById(agentId)?.name || 'Agente não encontrado'
                }}</span>
                <button
                  type="button"
                  class="ml-auto text-xs text-ruby-500 hover:text-ruby-600"
                  @click="removeAgent(agentId)"
                >
                  ✕
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Tab Agendamento -->
      <div
        v-if="activeTab === 'scheduling' && isStacklab === true"
        class="space-y-6"
      >
        <div class="flex items-center gap-3 mb-6">
          <div
            class="flex items-center justify-center w-8 h-8 rounded-lg bg-woot-50 dark:bg-woot-900/20"
          >
            <fluent-icon
              icon="calendar-clock"
              size="18"
              class="text-woot-500"
            />
          </div>
          <h4 class="text-base font-medium text-slate-800 dark:text-slate-100">
            {{ t('KANBAN.FORM.SCHEDULING.LABEL') }}
          </h4>
        </div>

        <div class="space-y-4">
          <div class="flex items-center">
            <input
              id="has-scheduling"
              v-model="showScheduling"
              type="checkbox"
              class="w-4 h-4 text-woot-500 border-slate-300 rounded focus:ring-woot-500"
            />
            <label
              for="has-scheduling"
              class="ml-2 text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.FORM.SCHEDULING.HAS_SCHEDULING') }}
            </label>
          </div>

          <div v-if="showScheduling" class="space-y-4">
            <div class="flex gap-6">
              <label class="flex items-center">
                <input
                  v-model="schedulingType"
                  type="radio"
                  value="deadline"
                  class="w-4 h-4 text-woot-500 border-slate-300 focus:ring-woot-500"
                />
                <span class="ml-2 text-sm text-slate-700 dark:text-slate-300">
                  {{ t('KANBAN.FORM.SCHEDULING.DEADLINE') }}
                </span>
              </label>
              <label class="flex items-center">
                <input
                  v-model="schedulingType"
                  type="radio"
                  value="schedule"
                  class="w-4 h-4 text-woot-500 border-slate-300 focus:ring-woot-500"
                />
                <span class="ml-2 text-sm text-slate-700 dark:text-slate-300">
                  {{ t('KANBAN.FORM.SCHEDULING.SCHEDULE') }}
                </span>
              </label>
            </div>

            <div v-if="schedulingType === 'schedule'" class="space-y-1.5">
              <label
                class="block text-sm font-medium text-slate-700 dark:text-slate-300"
              >
                {{ t('KANBAN.FORM.SCHEDULING.DATETIME') }}
              </label>
              <input
                v-model="form.item_details.scheduled_at"
                type="datetime-local"
                class="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
              />
            </div>

            <div v-else class="space-y-1.5">
              <label
                class="block text-sm font-medium text-slate-700 dark:text-slate-300"
              >
                {{ t('KANBAN.FORM.SCHEDULING.DEADLINE_DATE') }}
              </label>
              <input
                v-model="form.item_details.deadline_at"
                type="date"
                class="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
              />
            </div>
          </div>
        </div>
      </div>

      <!-- Tab Relacionamentos -->
      <div v-if="activeTab === 'relationships'" class="space-y-6">
        <div class="flex items-center gap-3 mb-6">
          <div
            class="flex items-center justify-center w-8 h-8 rounded-lg bg-woot-50 dark:bg-woot-900/20"
          >
            <fluent-icon icon="attach" size="18" class="text-woot-500" />
          </div>
          <h4 class="text-base font-medium text-slate-800 dark:text-slate-100">
            {{ t('KANBAN.TABS.RELATIONSHIPS') }}
          </h4>
        </div>

        <div class="space-y-4">
          <!-- Conversa -->
          <div class="space-y-3">
            <div class="flex items-center">
              <input
                id="has-conversation"
                v-model="showConversationInput"
                type="checkbox"
                class="w-4 h-4 text-woot-500 border-slate-300 rounded focus:ring-woot-500"
              />
              <label
                for="has-conversation"
                class="ml-2 text-sm font-medium text-slate-700 dark:text-slate-300"
              >
                {{ t('KANBAN.FORM.CONVERSATION.HAS_CONVERSATION') }}
              </label>
            </div>

            <div v-if="showConversationInput">
              <div ref="conversationSelectorRef" class="relative">
                <div
                  class="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg cursor-pointer focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
                  @click="openConversationDropdown"
                  tabindex="0"
                >
                  <span v-if="selectedConversation">
                    #{{ selectedConversation.id }} -
                    {{
                      selectedConversation.meta.sender.name ||
                      selectedConversation.meta.sender.email
                    }}
                  </span>
                  <span v-else class="text-slate-400">
                    {{ t('KANBAN.FORM.CONVERSATION.PLACEHOLDER') }}
                  </span>
                </div>
                <teleport to="body">
                  <div
                    v-if="conversationDropdownOpen"
                    :style="conversationDropdownStyle"
                    class="bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-lg max-h-96 overflow-y-auto"
                    @mousedown.stop
                  >
                    <input
                      v-model="conversationSearch"
                      type="text"
                      class="w-full px-3 py-2 mb-2 text-sm border-b border-slate-200 dark:border-slate-700 bg-transparent focus:outline-none"
                      placeholder="Buscar conversa..."
                    />
                    <div class="max-h-72 overflow-y-auto">
                      <div
                        v-for="conversation in filteredConversations"
                        :key="conversation.id"
                        class="px-3 py-2 hover:bg-woot-50 dark:hover:bg-slate-700 cursor-pointer text-sm"
                        @click="selectConversation(conversation.id)"
                      >
                        #{{ conversation.id }} -
                        {{
                          conversation.meta.sender.name ||
                          conversation.meta.sender.email
                        }}
                      </div>
                      <div
                        v-if="filteredConversations.length === 0"
                        class="px-3 py-2 text-slate-400 text-sm"
                      >
                        Nenhuma conversa encontrada
                      </div>
                    </div>
                  </div>
                </teleport>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Tab Campos Personalizados -->
      <div
        v-if="activeTab === 'custom_fields'"
        class="space-y-6"
        @click.prevent.stop
      >
        <!-- Campos Globais do Funil -->
        <div class="space-y-4">
          <h4 class="text-sm font-medium text-slate-700 dark:text-slate-300">
            {{ t('KANBAN.FORM.CUSTOM_FIELDS.GLOBAL_FIELDS') }}
          </h4>
          <div v-if="globalCustomAttributes.length > 0" class="space-y-4">
            <div
              v-for="(attr, idx) in globalCustomAttributes"
              :key="`global-${idx}`"
              class="p-4 bg-slate-50 dark:bg-slate-800/50 rounded-lg border border-slate-200 dark:border-slate-700"
            >
              <div class="flex items-center gap-3 mb-3">
                <span class="text-sm font-medium text-slate-700 dark:text-slate-300">
                  {{ attr.name }}
                </span>
                <span class="text-xs text-slate-500 dark:text-slate-400 bg-slate-200 dark:bg-slate-700 px-2 py-1 rounded">
                  {{ getFieldTypeLabel(attr.type) }}
                  {{ attr.is_list ? t('KANBAN.FORM.CUSTOM_FIELDS.LIST_INDICATOR') : '' }}
                </span>
              </div>

              <!-- Campo simples -->
              <div v-if="!attr.is_list">
                <input
                  v-model="globalCustomAttributesValues[attr.name]"
                  :type="attr.type === 'date' ? 'date' :
                         attr.type === 'number' ? 'number' : 'text'"
                  class="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
                  :placeholder="`${t('KANBAN.FORM.CUSTOM_FIELDS.ENTER_VALUE_FOR')} ${attr.name}`"
                />
              </div>

              <!-- Campo de lista -->
              <div v-else class="space-y-2">
                <div
                  v-for="(value, valueIdx) in globalCustomAttributesValues[attr.name] || []"
                  :key="`global-${idx}-value-${valueIdx}`"
                  class="flex items-center gap-2"
                >
                  <input
                    v-model="globalCustomAttributesValues[attr.name][valueIdx]"
                    :type="attr.type === 'date' ? 'date' :
                           attr.type === 'number' ? 'number' : 'text'"
                    class="flex-1 px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
                    :placeholder="`${t('KANBAN.FORM.CUSTOM_FIELDS.ITEM_NUMBER_FOR')} ${valueIdx + 1} ${t('KANBAN.FORM.CUSTOM_FIELDS.FOR_FIELD')} ${attr.name}`"
                  />
                  <button
                    type="button"
                    @click="() => removeGlobalListItem(attr.name, valueIdx)"
                    class="p-2 text-ruby-500 hover:text-ruby-600 dark:text-ruby-400 dark:hover:text-ruby-300 rounded transition-colors"
                    :disabled="(globalCustomAttributesValues[attr.name] || []).length <= 1"
                  >
                    <fluent-icon icon="dismiss" size="14" />
                  </button>
                </div>
                <button
                  type="button"
                  @click="() => addGlobalListItem(attr.name)"
                  class="mt-2 px-3 py-1 bg-woot-500 hover:bg-woot-600 text-white text-sm rounded transition-colors flex items-center gap-1"
                >
                  {{ t('KANBAN.FORM.CUSTOM_FIELDS.ADD_ITEM') }}
                  <fluent-icon icon="add" size="12" />
                </button>
              </div>
            </div>
          </div>
          <div v-else class="text-center py-4">
            <p class="text-sm text-slate-500">
              {{ t('KANBAN.FORM.CUSTOM_FIELDS.NO_GLOBAL_FIELDS') }}
            </p>
          </div>
        </div>

        <!-- Campos Personalizados Adicionais -->
        <div class="space-y-4">
          <h4 class="text-sm font-medium text-slate-700 dark:text-slate-300">
            {{ t('KANBAN.FORM.CUSTOM_FIELDS.ADDITIONAL_FIELDS') }}
          </h4>

          <div v-if="customAttributes.length === 0" class="text-center py-4">
            <p class="text-sm text-slate-500">
              {{ t('KANBAN.FORM.CUSTOM_FIELDS.EMPTY') }}
            </p>
          </div>

          <div v-else class="space-y-4" @click.prevent.stop>
            <div
              v-for="(attr, idx) in customAttributes"
              :key="idx"
              class="flex gap-2 items-center"
              @click.prevent.stop
            >
              <input
                v-model="attr.name"
                type="text"
                class="w-1/2 px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
                :placeholder="t('KANBAN.FORM.CUSTOM_FIELDS.KEY_PLACEHOLDER')"
              />
              <select
                v-model="attr.type"
                class="w-1/2 px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
              >
                <option value="string">{{ t('KANBAN.FORM.CUSTOM_FIELDS.TYPE_TEXT') }}</option>
                <option value="number">{{ t('KANBAN.FORM.CUSTOM_FIELDS.TYPE_NUMBER') }}</option>
                <option value="date">{{ t('KANBAN.FORM.CUSTOM_FIELDS.TYPE_DATE') }}</option>
                <option value="boolean">{{ t('KANBAN.FORM.CUSTOM_FIELDS.TYPE_BOOLEAN') }}</option>
              </select>
              <button
                type="button"
                @click="removeCustomAttribute(idx)"
                class="p-1 text-ruby-500 hover:text-ruby-600 dark:text-ruby-400 dark:hover:text-ruby-300 rounded transition-colors"
              >
                ✕
              </button>
            </div>
            <button
              type="button"
              @click="addCustomAttribute"
              class="mt-2 px-3 py-1 bg-woot-500 hover:bg-woot-600 text-white rounded transition-colors"
            >
              {{ t('KANBAN.FORM.CUSTOM_FIELDS.ADD_FIELD') }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Botões -->
    <div class="flex justify-end space-x-2 pt-4 p-3">
      <Button
        type="button"
        variant="ghost"
        color="slate"
        size="sm"
        @click="emit('close')"
      >
        {{ t('KANBAN.CANCEL') }}
      </Button>
      <Button
        type="submit"
        variant="solid"
        color="blue"
        size="sm"
        :isLoading="loading"
      >
        {{ t('KANBAN.SAVE') }}
      </Button>
    </div>
  </form>
</template>

<style lang="scss" scoped>
// Efeito de foco nos inputs
input,
textarea {
  @apply transition-shadow duration-200;

  &:focus {
    @apply shadow-md;
  }
}

// Animação suave do checkbox
input[type='checkbox'] {
  @apply transition-transform duration-200;

  &:checked {
    @apply scale-105;
  }
}

.loading-spinner {
  @apply w-4 h-4 border-2 border-slate-200 border-t-woot-500 rounded-full animate-spin;
}

input[type='date'],
input[type='datetime-local'] {
  &::-webkit-calendar-picker-indicator {
    @apply dark:invert cursor-pointer;
  }
}

input[type='checkbox'],
input[type='radio'] {
  @apply cursor-pointer;
}

select {
  @apply cursor-pointer;
}

label {
  @apply cursor-pointer;
}

// Estilização do scroll
::-webkit-scrollbar {
  @apply w-2;
}

::-webkit-scrollbar-track {
  @apply bg-transparent;
}

::-webkit-scrollbar-thumb {
  @apply bg-slate-300 dark:bg-slate-600 rounded-full;

  &:hover {
    @apply bg-slate-400 dark:bg-slate-500;
  }
}

// Ajuste para o scroll
form {
  @apply min-w-0 w-full transition-all;
}

// Ajuste para os grids responsivos
.grid {
  @apply min-w-0 w-full;
}

// Estilos das tabs
.tabs-container {
  @apply -mx-2;
  overflow: visible;
  min-height: 48px; /* Altura mínima para garantir visibilidade */
}

.tabs-scroll-wrapper {
  display: flex;
  overflow-x: auto;
  overflow-y: visible;
  scrollbar-width: thin; /* Firefox - mostrar scrollbar fina */
  -ms-overflow-style: -ms-autohiding-scrollbar; /* IE and Edge */
  scroll-behavior: smooth;
  padding-bottom: 4px; /* Espaço para scrollbar */
  min-height: 48px; /* Altura mínima */
}

.tabs-scroll-wrapper::-webkit-scrollbar {
  height: 4px; /* Altura da scrollbar */
}

.tabs-scroll-wrapper::-webkit-scrollbar-track {
  background: transparent;
}

.tabs-scroll-wrapper::-webkit-scrollbar-thumb {
  background: rgba(148, 163, 184, 0.3); /* Cor da scrollbar */
  border-radius: 2px;

  &:hover {
    background: rgba(148, 163, 184, 0.5);
  }
}

.tab-button {
  @apply relative px-4 py-3 text-sm font-medium transition-colors whitespace-nowrap flex-shrink-0;
  min-width: fit-content;
  max-width: 120px; /* Largura máxima para evitar botões muito largos */
}

.tab-active {
  @apply text-woot-500;

  &::after {
    content: '';
    @apply absolute bottom-0 left-0 right-0 h-0.5 bg-woot-500;
  }
}

.tab-inactive {
  @apply text-slate-500 dark:text-slate-400 hover:text-slate-700 dark:hover:text-slate-300;
}

/* Mobile: ajustes específicos para abas */
@media (max-width: 768px) {
  .tabs-container {
    @apply -mx-1; /* Menos margem negativa em mobile */
    min-height: 44px;
  }

  .tabs-scroll-wrapper {
    min-height: 44px;
    padding-bottom: 6px; /* Mais espaço para scrollbar em mobile */
  }

  .tab-button {
    @apply px-3 py-2 text-xs;
    min-width: fit-content;
    max-width: 100px; /* Menor largura máxima em mobile */

    // Quebrar texto se necessário
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  // Garantir que pelo menos parte das abas seja sempre visível
  .tabs-scroll-wrapper {
    scroll-snap-type: x mandatory;

    .tab-button {
      scroll-snap-align: start;
    }
  }
}

/* Extra small screens */
@media (max-width: 480px) {
  .tab-button {
    @apply px-2 py-2 text-xs;
    min-width: 80px;
    max-width: 80px;
  }

  .tabs-container {
    min-height: 40px;
  }

  .tabs-scroll-wrapper {
    min-height: 40px;
  }
}

// Cards com cores diferentes
.info-card {
  @apply relative overflow-hidden flex flex-col gap-1 p-3 rounded-lg transition-all duration-200;

  &:nth-child(1) {
    @apply bg-n-iris-3 dark:bg-n-slate-8 border-n-iris-4 dark:border-n-iris-8/50;
  }

  &:nth-child(2) {
    @apply bg-n-teal-3 dark:bg-n-slate-8 border-n-teal-4 dark:border-n-teal-8/50;
  }

  &:nth-child(3) {
    @apply bg-n-amber-3 dark:bg-n-slate-8 border-n-amber-4 dark:border-n-amber-8/50;
  }

  &:nth-child(4) {
    @apply bg-n-iris-3 dark:bg-n-slate-8 border-n-iris-4 dark:border-n-iris-8/50;
  }
}
</style>
