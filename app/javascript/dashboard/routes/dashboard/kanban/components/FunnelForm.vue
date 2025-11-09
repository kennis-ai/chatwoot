<script setup>
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useConfig } from 'dashboard/composables/useConfig';
import FunnelAPI from '../../../../api/funnel';
import StageColorPicker from './StageColorPicker.vue';
import draggable from 'vuedraggable';
import agents from '../../../../api/agents';
import inboxesAPI from '../../../../api/inboxes';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

import { reactive } from 'vue';

const props = defineProps({
  isEditing: {
    type: Boolean,
    default: false,
  },
  funnelId: {
    type: [String, Number],
    default: null,
  },
  initialData: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['saved', 'close', 'metadata-updated']);
const { t } = useI18n();
const { isStacklab } = useConfig();
const loading = ref(false);
const errorMessage = ref('');
const leftColumnCollapsed = ref(false);
const globalFieldsCollapsed = ref(false);
const stagesCollapsed = ref(false);
const agentsCollapsed = ref(false);
const templatesCollapsed = ref(false);
const goalsCollapsed = ref(false);
const lossWinReasonsCollapsed = ref(false);
const checklistPresetsCollapsed = ref(false);

// Dados das metas
const goals = ref([]);
const newGoal = ref({
  id: '',
  type: 'conversion_rate',
  value: '',
  description: '',
});

const editingGoal = ref(null);

// Motivos de perda e ganho
const lossReasons = ref([]);
const winReasons = ref([]);
const newReason = ref({
  type: 'loss', // 'loss' ou 'win'
  title: '',
  description: '',
});
const editingReason = ref(null);

// Checklist presets
const selectedStageForChecklist = ref(null);
const newChecklistItem = ref({
  text: '',
  priority: 'none',
  required: false,
});
const editingChecklistItem = ref(null);

const formData = ref({
  name: '',
  description: '',
  active: true,
  stages: {},
  settings: {},
  agents: [],
  global_custom_attributes: [],
});

// Campos adicionais para exibição
const funnelMetadata = ref({
  updated_at: null,
  optimization_history: [],
});

const stages = ref([]);
const newStage = ref({
  name: '',
  color: '#FF6B6B',
  description: '',
  auto_create_conditions: [],
});

const editingStage = ref(null);

const dragOptions = {
  animation: 150,
  ghostClass: 'ghost-card',
};

const vFocus = {
  mounted: el => el.focus(),
};

const agentsList = ref([]);
const loadingAgents = ref(false);
const existingStageIds = ref(new Set());
const stageStats = ref({});
const loadingStats = ref(false);

const newCondition = ref({
  type: 'contact_has_tag',
  value: '',
  attribute: '',
  operator: 'equal_to',
});

// Gera o ID baseado no nome
const generateId = name => {
  return name
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
};

// Gera um ID único apenas se necessário
const generateUniqueId = (baseName, existingStages, currentId = null) => {
  // Se já tem um ID e está editando, mantém o mesmo
  if (currentId && editingStage.value) {
    return currentId;
  }

  const baseId = generateId(baseName);
  const stageIds = existingStages.map(stage => stage.id);

  // Se o ID base não existe, usa ele
  if (!stageIds.includes(baseId)) {
    return baseId;
  }

  // Se existe, adiciona um timestamp para garantir unicidade
  return `${baseId}_${Date.now()}`;
};

// Atualiza o ID apenas para novas etapas
watch(
  () => newStage.value.name,
  newName => {
    if (newName && !editingStage.value) {
      newStage.value.id = generateId(newName);
    }
  }
);

// Converte as etapas para o formato esperado pela API
const formatStagesForAPI = () => {
  const formattedStages = {};

  // Garantir que as posições reflitam a ordem atual
  stages.value.forEach((stage, index) => {
    // Definir explicitamente a posição baseada no índice atual
    const position = index + 1;

    // Pega os templates existentes da etapa atual
    const existingTemplates =
      formData.value.stages?.[stage.id]?.message_templates || [];

    formattedStages[stage.id] = {
      name: stage.name,
      color: stage.color,
      position: position, // Garantir que a posição reflita a ordem atual
      description: stage.description,
      auto_create_conditions: stage.auto_create_conditions || [],
      message_templates: existingTemplates, // Mantém os templates existentes
      checklist_templates: stage.checklist_templates || [],
    };
  });

  return formattedStages;
};

// Função para lidar com a reordenação das etapas
const handleOrderChange = async () => {
  if (!props.isEditing) return;

  try {
    // Atualizar as posições com base na nova ordem
    stages.value.forEach((stage, index) => {
      stage.position = index + 1;
    });

    const payload = {
      name: formData.value.name,
      description: formData.value.description,
      stages: formatStagesForAPI(),
    };

    // Atualiza o estado local sem fazer chamada à API
    formData.value.stages = payload.stages;
  } catch (error) {
    // Error handling
  }
};

const handleAddStage = e => {
  if (e?.target?.closest('.colorpicker--chrome')) {
    return;
  }

  if (!newStage.value.name) return;

  if (editingStage.value) {
    const index = stages.value.findIndex(s => s.id === editingStage.value.id);
    if (index !== -1) {
      stages.value[index] = {
        ...editingStage.value,
        name: newStage.value.name,
        color: newStage.value.color,
        description: newStage.value.description,
        auto_create_conditions: newStage.value.auto_create_conditions,
        checklist_templates: editingStage.value.checklist_templates || [],
        id: editingStage.value.id,
      };
      if (props.isEditing) {
        handleOrderChange();
      }
    }
    editingStage.value = null;
  } else {
    let stageId = generateId(newStage.value.name);
    let counter = 1;
    while (existingStageIds.value.has(stageId)) {
      stageId = `${generateId(newStage.value.name)}_${counter}`;
      counter++;
    }
    stages.value.push({
      ...newStage.value,
      id: stageId,
      checklist_templates: [],
    });
    existingStageIds.value.add(stageId);
  }
  newStage.value = {
    name: '',
    color: '#FF6B6B',
    description: '',
    auto_create_conditions: [],
  };
};

const removeStage = index => {
  stages.value.splice(index, 1);
};

// Busca todos os funis e coleta os IDs existentes
const fetchExistingStageIds = async () => {
  try {
    const { data: allFunnels } = await FunnelAPI.get();
    existingStageIds.value.clear();

    allFunnels.forEach(funnel => {
      if (funnel.id !== props.funnelId) {
        // Ignora o funil atual se estiver editando
        Object.keys(funnel.stages || {}).forEach(id => {
          existingStageIds.value.add(id);
        });
      }
    });
  } catch (error) {
    // Error handling
  }
};

// Inicializa o formulário
onMounted(async () => {
  // Carrega agentes e inboxes sempre
  await Promise.all([fetchAgents(), fetchInboxes()]);

  // Carrega dados do funil se estiver editando
  if (props.isEditing && props.funnelId) {
    await fetchFunnelData();
    await fetchStageStats();
  }

  // Se estiver criando e existir initialData vindo de template, hidrata o formulário
  if (!props.isEditing && props.initialData) {
    formData.value.name = props.initialData.name || '';
    formData.value.description = props.initialData.description || '';
    formData.value.active = true;
    formData.value.stages = props.initialData.stages || {};
    formData.value.settings = props.initialData.settings || {};
    formData.value.agents = props.initialData.settings?.agents || [];

    // Inicializa lista de etapas ordenadas
    stages.value = Object.entries(formData.value.stages)
      .map(([id, stage]) => ({
        id,
        name: stage.name,
        color: stage.color,
        description: stage.description,
        position: parseInt(stage.position, 10) || 0,
        auto_create_conditions: stage.auto_create_conditions || [],
        message_templates: stage.message_templates || [],
        checklist_templates: stage.checklist_templates || [],
      }))
      .sort((a, b) => a.position - b.position);
  }

  // Garante que sempre tenha pelo menos um campo customizado vazio
  if (
    !Array.isArray(formData.value.global_custom_attributes) ||
    formData.value.global_custom_attributes.length === 0
  ) {
    formData.value.global_custom_attributes = [
      { name: '', type: '', field_type: 'single', list_values: [] },
    ];
  }

  // Adiciona listener para evento personalizado de salvar
  const formElement = document.querySelector('.funnel-form');
  if (formElement) {
    formElement.addEventListener('save-form', handleSubmit);
  }

  // Cleanup do listener quando o componente for desmontado
  onUnmounted(() => {
    if (formElement) {
      formElement.removeEventListener('save-form', handleSubmit);
    }
  });
});

const fetchAgents = async () => {
  try {
    loadingAgents.value = true;
    const { data } = await agents.get();
    agentsList.value = data;
  } catch (error) {
    // Error handling
  } finally {
    loadingAgents.value = false;
  }
};

const fetchInboxes = async () => {
  try {
    loadingInboxes.value = true;
    const response = await inboxesAPI.get();
    inboxes.value = response.data.payload || [];
  } catch (error) {
    inboxes.value = [];
  } finally {
    loadingInboxes.value = false;
  }
};

const fetchStageStats = async () => {
  if (!props.isEditing || !props.funnelId) return;

  try {
    loadingStats.value = true;
    const response = await FunnelAPI.getStageStats(props.funnelId, {});
    stageStats.value = response.data.stages || {};
  } catch (error) {
    console.error('Erro ao buscar estatísticas:', error);
    stageStats.value = {};
  } finally {
    loadingStats.value = false;
  }
};

const fetchFunnelData = async () => {
  if (!props.isEditing || !props.funnelId) return;

  try {
    loading.value = true;
    const response = await FunnelAPI.getById(props.funnelId);
    const funnelData = response.data;

    // Definir cada propriedade individualmente para garantir reatividade
    formData.value.name = funnelData.name || '';
    formData.value.description = funnelData.description || '';
    formData.value.active =
      funnelData.active !== undefined ? funnelData.active : true;
    formData.value.stages = funnelData.stages || {};
    formData.value.settings = funnelData.settings || {};
    formData.value.agents = funnelData.settings?.agents || [];
    formData.value.global_custom_attributes = Array.isArray(
      funnelData.global_custom_attributes
    )
      ? funnelData.global_custom_attributes.map(attr => ({
          name: attr.name || '',
          type: attr.type || '',
          field_type: attr.is_list ? 'list' : 'single',
          list_values: attr.list_values || [],
        }))
      : [];

    // Armazenar metadados para exibição
    funnelMetadata.value = {
      updated_at: funnelData.updated_at,
      optimization_history: funnelData.settings?.optimization_history || [],
    };

    // Emitir metadados para o header
    emit('metadata-updated', {
      updated_at: funnelData.updated_at,
      name: funnelData.name,
    });

    // Se tiver agentes pré-selecionados e eles não estiverem na lista, adiciona-os
    if (funnelData.settings?.agents?.length) {
      funnelData.settings.agents.forEach(agent => {
        if (!agentsList.value.find(a => a.id === agent.id)) {
          agentsList.value.push(agent);
        }
      });
    }

    // Inicializa as metas
    goals.value = funnelData.settings?.goals || [];

    // Inicializa os motivos de perda e ganho
    lossReasons.value = funnelData.settings?.loss_reasons || [];
    winReasons.value = funnelData.settings?.win_reasons || [];

    // Inicializa as etapas do template
    if (funnelData.stages) {
      stages.value = Object.entries(funnelData.stages)
        .map(([id, stage]) => ({
          id,
          name: stage.name,
          color: stage.color,
          description: stage.description,
          position: parseInt(stage.position, 10) || 0,
          auto_create_conditions: stage.auto_create_conditions || [],
          checklist_templates: stage.checklist_templates || [],
        }))
        .sort((a, b) => a.position - b.position);
    }
  } catch (error) {
    errorMessage.value = 'Erro ao carregar dados do funil';
  } finally {
    loading.value = false;
  }
};

// Funções para gerenciar condições
const addCondition = () => {
  const conditionlessTypes = [
    'message_not_read',
    'conversation_unassigned',
    'conversation_reopened',
    'conversation_snoozed',
  ];
  if (
    !conditionlessTypes.includes(newCondition.value.type) &&
    (!newCondition.value.value ||
      newCondition.value.value.toString().trim() === '')
  )
    return;

  const condition = { ...newCondition.value };

  // Para condições que não precisam de operador, remove o campo
  if (conditionlessTypes.includes(newCondition.value.type)) {
    delete condition.operator;
    delete condition.attribute;
  }

  newStage.value.auto_create_conditions.push(condition);

  // Reset do formulário de condição
  newCondition.value = {
    type: 'contact_has_tag',
    value: '',
    attribute: '',
    operator: 'equal_to',
  };
};

const removeCondition = index => {
  newStage.value.auto_create_conditions.splice(index, 1);
};

const getConditionTypeLabel = type => {
  const labels = {
    contact_has_tag: 'Contato tem tag',
    contact_has_custom_attribute: 'Atributo customizado',
    message_contains: 'Mensagem contém',
    conversation_has_priority: 'Prioridade da conversa',
    inbox_matches: 'Inbox específico',
    message_is_private: 'Mensagem privada contém',
    message_has_automation: 'Mensagem por automação contém',
    conversation_message_count: 'Quantidade de mensagens',
    last_message_age: 'Idade da última mensagem',
    message_not_read: 'Mensagem não lida',
    conversation_unassigned: 'Conversa sem agente',
    conversation_reopened: 'Conversa reaberta',
    conversation_snoozed: 'Conversa adiada',
  };
  return labels[type] || type;
};

const getOperatorLabel = operator => {
  const labels = {
    equal_to: 'Igual a',
    contains: 'Contém',
    not_equal_to: 'Diferente de',
    greater_than: 'Maior que',
    less_than: 'Menor que',
    greater_than_or_equal: 'Maior ou igual a',
    less_than_or_equal: 'Menor ou igual a',
  };
  return labels[operator] || operator;
};

// Funções para manipular campos personalizados globais
const globalCustomAttributes = computed({
  get: () => formData.value.global_custom_attributes,
  set: val => {
    formData.value.global_custom_attributes = val;
  },
});

function addGlobalCustomAttribute() {
  globalCustomAttributes.value.push({
    name: '',
    type: '',
    field_type: 'single',
    list_values: [],
  });
}

function removeGlobalCustomAttribute(index) {
  globalCustomAttributes.value.splice(index, 1);
}

function addListValue(attrIndex) {
  if (!globalCustomAttributes.value[attrIndex].list_values) {
    globalCustomAttributes.value[attrIndex].list_values = [];
  }
  globalCustomAttributes.value[attrIndex].list_values.push('');
}

function removeListValue(attrIndex, valueIndex) {
  globalCustomAttributes.value[attrIndex].list_values.splice(valueIndex, 1);
}

const handleSubmit = async () => {
  try {
    loading.value = true;
    errorMessage.value = '';

    // Verifica o limite de funis para versão não PRO
    if (!isStacklab && !props.isEditing) {
      const { data: existingFunnels } = await FunnelAPI.get();
      if (existingFunnels.length >= 2) {
        errorMessage.value = t('KANBAN.FUNNELS.FORM.ERROR_LIMIT_REACHED');
        return;
      }
    }

    // Preparar as etapas mantendo os templates existentes e atualizando posições
    const formattedStages = formatStagesForAPI();

    const payload = {
      name: formData.value.name,
      description: formData.value.description,
      active: formData.value.active,
      stages: formattedStages,
      settings: {
        agents: formData.value.agents,
        goals: goals.value.filter(
          goal => goal.value && goal.value.toString().trim() !== ''
        ),
        loss_reasons: lossReasons.value.filter(r => r.title.trim() !== ''),
        win_reasons: winReasons.value.filter(r => r.title.trim() !== ''),
      },
      global_custom_attributes: formData.value.global_custom_attributes
        .filter(attr => attr.name.trim() !== '' && attr.type.trim() !== '')
        .map(attr => {
          const base = {
            name: attr.name,
            type: attr.type,
            is_list: attr.field_type === 'list',
          };
          if (attr.field_type === 'list') {
            base.list_values = (attr.list_values || []).filter(
              v => v.trim() !== ''
            );
          }
          return base;
        }),
    };

    let response;
    if (props.isEditing) {
      // Se estiver editando, faz update na API
      response = await FunnelAPI.update(props.funnelId, payload);
    } else {
      response = await FunnelAPI.create(payload);
    }

    if (response.data) {
      emit('saved', response.data);
    }
  } catch (error) {
    if (error.response?.data?.code === 'FUNNEL_LIMIT_REACHED') {
      errorMessage.value = error.response.data.error;
    } else {
      errorMessage.value = t('KANBAN.FUNNELS.FORM.ERROR_GENERIC');
    }
  } finally {
    loading.value = false;
  }
};

const startEditing = stage => {
  newStage.value = {
    id: stage.id,
    name: stage.name,
    color: stage.color,
    description: stage.description,
    auto_create_conditions: stage.auto_create_conditions || [],
    checklist_templates: stage.checklist_templates || [],
  };
  editingStage.value = stage;
};

const saveStageEdit = index => {
  if (!editingStage.value) return;

  stages.value[index] = {
    ...stages.value[index],
    name: editingStage.value.name,
    description: editingStage.value.description,
    color: editingStage.value.color,
    auto_create_conditions: editingStage.value.auto_create_conditions,
    checklist_templates: stages.value[index].checklist_templates || [],
  };

  editingStage.value = null;

  // Se estiver editando, atualiza imediatamente
  if (props.isEditing) {
    handleOrderChange();
  }
};

const cancelEditing = () => {
  editingStage.value = null;
  // Limpa o formulário de nova etapa
  newStage.value = {
    name: '',
    color: '#FF6B6B',
    description: '',
    auto_create_conditions: [],
  };
};

// Watch para agentes
watch(
  () => formData.value.agents,
  newAgents => {
    // Handle agents update
  }
);

const toggleAgent = agent => {
  const index = formData.value.agents.findIndex(a => a.id === agent.id);
  if (index === -1) {
    formData.value.agents.push(agent);
  } else {
    formData.value.agents.splice(index, 1);
  }
};

// Computed para validar se pode adicionar condição
const canAddCondition = computed(() => {
  const conditionlessTypes = [
    'message_not_read',
    'conversation_unassigned',
    'conversation_reopened',
    'conversation_snoozed',
  ];
  if (conditionlessTypes.includes(newCondition.value.type)) {
    return true;
  }
  return (
    newCondition.value.value &&
    newCondition.value.value.toString().trim() !== ''
  );
});

// Watch para atualizar unidade automaticamente baseada no tipo de meta
watch(
  () => newGoal.value.type,
  newType => {
    const unitMap = {
      conversion_rate: 'percentage',
      average_value: 'currency',
      average_time: 'days',
      total_conversions: 'count',
      total_revenue: 'currency',
    };
    newGoal.value.unit = unitMap[newType] || 'count';
  }
);

// Watch para monitorar mudanças nas etapas
watch(
  () => stages.value,
  newStages => {
    // Handle stages update
  },
  { deep: true }
);

watch(
  () => formData.value,
  newFormData => {
    // Handle formData update
  },
  { deep: true }
);

watch(
  () => formData.value.global_custom_attributes,
  val => {
    if (!Array.isArray(val) || val.length === 0) {
      formData.value.global_custom_attributes = [
        { name: '', type: '', field_type: 'single', list_values: [] },
      ];
    }
  },
  { immediate: true }
);

const agentSearch = ref('');
const agentDropdownOpen = ref(false);
const agentSelectorRef = ref(null);
const filteredAgents = computed(() => {
  if (!agentSearch.value)
    return agentsList.value.filter(
      a => !formData.value.agents.some(sel => sel.id === a.id)
    );
  return agentsList.value.filter(
    a =>
      !formData.value.agents.some(sel => sel.id === a.id) &&
      a.name.toLowerCase().includes(agentSearch.value.toLowerCase())
  );
});

const inboxes = ref([]);
const loadingInboxes = ref(false);
function addAgent(agent) {
  if (!formData.value.agents.some(a => a.id === agent.id))
    formData.value.agents.push(agent);
  agentDropdownOpen.value = false;
  agentSearch.value = '';
}
function removeAgent(agent) {
  formData.value.agents = formData.value.agents.filter(a => a.id !== agent.id);
}
function closeAgentDropdown(e) {
  if (!agentSelectorRef.value?.contains(e.target)) {
    agentDropdownOpen.value = false;
    window.removeEventListener('click', closeAgentDropdown);
  }
}
function openAgentDropdown() {
  agentDropdownOpen.value = true;
  setTimeout(() => {
    window.removeEventListener('click', closeAgentDropdown);
    window.addEventListener('click', closeAgentDropdown);
  }, 0);
}

// Controle de tooltip de cópia por etapa
const copiedStageId = ref({});
const showHelpPopover = ref(false);

// Função para copiar o id da etapa
async function copyStageId(id) {
  navigator.clipboard.writeText(id);
  copiedStageId.value[id] = true;
  await nextTick();
  setTimeout(() => {
    copiedStageId.value[id] = false;
  }, 1500);
}

// Controle de expansão/colapso das etapas na pré-visualização

// Função para formatar valores monetários
const formatCurrency = value => {
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(value || 0);
};

// Função para calcular total de templates de mensagem
const getTotalMessageTemplates = () => {
  return stages.value.reduce((total, stage) => {
    return total + (stage.message_templates || []).length;
  }, 0);
};

// Função para alternar o estado da coluna esquerda
const toggleLeftColumn = () => {
  leftColumnCollapsed.value = !leftColumnCollapsed.value;
};

// Função para alternar o estado dos campos globais
const toggleGlobalFields = () => {
  globalFieldsCollapsed.value = !globalFieldsCollapsed.value;
};

// Função para alternar o estado das etapas
const toggleStages = () => {
  if (stagesCollapsed.value) {
    // Se está colapsado e vai expandir, colapsa os outros
    agentsCollapsed.value = true;
    templatesCollapsed.value = true;
  }
  stagesCollapsed.value = !stagesCollapsed.value;
};

// Função para alternar o estado dos agentes
const toggleAgents = () => {
  if (agentsCollapsed.value) {
    // Se está colapsado e vai expandir, colapsa os outros
    stagesCollapsed.value = true;
    templatesCollapsed.value = true;
  }
  agentsCollapsed.value = !agentsCollapsed.value;
};

// Função para alternar o estado dos templates
const toggleTemplates = () => {
  if (templatesCollapsed.value) {
    // Se está colapsado e vai expandir, colapsa os outros
    stagesCollapsed.value = true;
    agentsCollapsed.value = true;
  }
  templatesCollapsed.value = !templatesCollapsed.value;
};

// Funções para gerenciar metas
const generateGoalId = () => {
  return `goal_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
};

const addGoal = () => {
  if (!newGoal.value.value) return;

  if (editingGoal.value) {
    const index = goals.value.findIndex(g => g.id === editingGoal.value.id);
    if (index !== -1) {
      goals.value[index] = {
        ...editingGoal.value,
        type: newGoal.value.type,
        value: newGoal.value.value,
        unit: newGoal.value.unit,
        description: newGoal.value.description,
        id: editingGoal.value.id,
      };
    }
    editingGoal.value = null;
  } else {
    goals.value.push({
      ...newGoal.value,
      id: generateGoalId(),
    });
  }

  newGoal.value = {
    id: '',
    type: 'conversion_rate',
    value: '',
    description: '',
  };
};

const removeGoal = index => {
  goals.value.splice(index, 1);
};

const startEditingGoal = goal => {
  newGoal.value = {
    id: goal.id,
    type: goal.type,
    value: goal.value,
    unit: goal.unit,
    description: goal.description,
  };
  editingGoal.value = goal;
};

const cancelEditingGoal = () => {
  editingGoal.value = null;
  newGoal.value = {
    id: '',
    type: 'conversion_rate',
    value: '',
    description: '',
  };
};

const getGoalTypeLabel = type => {
  const labels = {
    conversion_rate: t('KANBAN.FUNNELS.FORM.GOALS.TYPES.CONVERSION_RATE'),
    average_value: t('KANBAN.FUNNELS.FORM.GOALS.TYPES.AVERAGE_VALUE'),
    average_time: t('KANBAN.FUNNELS.FORM.GOALS.TYPES.AVERAGE_TIME'),
    total_conversions: t('KANBAN.FUNNELS.FORM.GOALS.TYPES.TOTAL_CONVERSIONS'),
    total_revenue: t('KANBAN.FUNNELS.FORM.GOALS.TYPES.TOTAL_REVENUE'),
  };
  return labels[type] || type;
};

const getUnitLabel = unit => {
  const labels = {
    percentage: '%',
    currency: 'R$',
    days: 'dias',
    hours: 'horas',
    count: '',
  };
  return labels[unit] || '';
};

// Função para alternar o estado das metas
const toggleGoals = () => {
  if (goalsCollapsed.value) {
    // Se está colapsado e vai expandir, colapsa os outros
    stagesCollapsed.value = true;
    agentsCollapsed.value = true;
    templatesCollapsed.value = true;
  }
  goalsCollapsed.value = !goalsCollapsed.value;
};

// Funções para gerenciar motivos de perda e ganho
const addReason = () => {
  if (!newReason.value.title.trim()) return;

  const targetArray =
    newReason.value.type === 'loss' ? lossReasons : winReasons;

  if (editingReason.value) {
    const index = targetArray.value.findIndex(
      r => r.id === editingReason.value.id
    );
    if (index !== -1) {
      targetArray.value[index] = {
        ...editingReason.value,
        title: newReason.value.title,
        description: newReason.value.description,
      };
    }
    editingReason.value = null;
  } else {
    targetArray.value.push({
      id: `reason_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      title: newReason.value.title,
      description: newReason.value.description,
    });
  }

  newReason.value = { type: 'loss', title: '', description: '' };
};

const removeReason = (type, index) => {
  const targetArray = type === 'loss' ? lossReasons : winReasons;
  targetArray.value.splice(index, 1);
};

const startEditingReason = (type, reason) => {
  newReason.value = {
    type,
    title: reason.title,
    description: reason.description,
  };
  editingReason.value = reason;
};

const cancelEditingReason = () => {
  editingReason.value = null;
  newReason.value = { type: 'loss', title: '', description: '' };
};

const toggleLossWinReasons = () => {
  if (lossWinReasonsCollapsed.value) {
    stagesCollapsed.value = true;
    agentsCollapsed.value = true;
    templatesCollapsed.value = true;
    goalsCollapsed.value = true;
  }
  lossWinReasonsCollapsed.value = !lossWinReasonsCollapsed.value;
};

const toggleChecklistPresets = () => {
  if (checklistPresetsCollapsed.value) {
    stagesCollapsed.value = true;
    agentsCollapsed.value = true;
    templatesCollapsed.value = true;
    goalsCollapsed.value = true;
    lossWinReasonsCollapsed.value = true;
  }
  checklistPresetsCollapsed.value = !checklistPresetsCollapsed.value;
};

// Funções para gerenciar checklist presets
const addChecklistPreset = () => {
  if (!newChecklistItem.value.text.trim() || !selectedStageForChecklist.value)
    return;

  const stage = stages.value.find(
    s => s.id === selectedStageForChecklist.value
  );
  if (!stage) return;

  if (!stage.checklist_templates) {
    stage.checklist_templates = [];
  }

  if (editingChecklistItem.value) {
    const index = stage.checklist_templates.findIndex(
      c => c.id === editingChecklistItem.value.id
    );
    if (index !== -1) {
      stage.checklist_templates[index] = {
        ...editingChecklistItem.value,
        text: newChecklistItem.value.text,
        priority: newChecklistItem.value.priority,
        required: newChecklistItem.value.required,
      };
    }
    editingChecklistItem.value = null;
  } else {
    stage.checklist_templates.push({
      id: `checklist_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      text: newChecklistItem.value.text,
      priority: newChecklistItem.value.priority,
      required: newChecklistItem.value.required,
    });
  }

  newChecklistItem.value = { text: '', priority: 'none', required: false };
};

const removeChecklistPreset = (stageId, index) => {
  const stage = stages.value.find(s => s.id === stageId);
  if (!stage || !stage.checklist_templates) return;
  stage.checklist_templates.splice(index, 1);
};

const startEditingChecklistPreset = item => {
  newChecklistItem.value = {
    text: item.text,
    priority: item.priority,
    required: item.required || false,
  };
  editingChecklistItem.value = item;
};

const cancelEditingChecklistPreset = () => {
  editingChecklistItem.value = null;
  newChecklistItem.value = { text: '', priority: 'none', required: false };
};

const getChecklistPresetPriority = priority => {
  const priorityMap = {
    none: { label: 'Nenhuma', color: 'slate' },
    low: { label: 'Baixa', color: 'green' },
    medium: { label: 'Média', color: 'yellow' },
    high: { label: 'Alta', color: 'orange' },
    urgent: { label: 'Urgente', color: 'red' },
  };
  return priorityMap[priority] || priorityMap.none;
};
</script>

<template>
  <form class="funnel-form scrollbar-hide" @submit.prevent="handleSubmit">
    <!-- Mensagem de erro -->
    <div
      v-if="errorMessage"
      class="mb-4 p-4 bg-ruby-50 dark:bg-ruby-900/20 border border-ruby-200 dark:border-ruby-800 rounded-lg"
    >
      <div class="flex items-center gap-2">
        <fluent-icon
          icon="error-circle"
          size="20"
          class="text-ruby-500 dark:text-ruby-300"
        />
        <span class="text-ruby-700 dark:text-ruby-200">{{ errorMessage }}</span>
      </div>
    </div>

    <div
      class="grid grid-cols-1 md:grid-cols-[1fr_400px] gap-6 md:gap-6 gap-y-6"
    >
      <!-- Coluna Esquerda - Formulário -->
      <div class="space-y-6">
        <!-- Toggle e Título -->
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2 text-base font-medium">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="lucide lucide-file-text-icon lucide-file-text"
            >
              <path
                d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"
              />
              <path d="M14 2v4a2 2 0 0 0 2 2h4" />
              <path d="M10 9H8" />
              <path d="M16 13H8" />
              <path d="M16 17H8" />
            </svg>
            {{ t('KANBAN.FUNNELS.FORM.SECTIONS.BASIC_DATA') }}
          </div>
          <div class="flex-1 mx-4 h-px bg-slate-200 dark:bg-slate-700" />
          <button
            type="button"
            class="flex items-center justify-center w-8 h-8 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800"
            @click="toggleLeftColumn"
          >
            <fluent-icon
              :icon="leftColumnCollapsed ? 'chevron-down' : 'chevron-up'"
              size="16"
            />
          </button>
        </div>

        <!-- Conteúdo colapsável -->
        <div v-show="!leftColumnCollapsed">
          <!-- Status Ativo -->
          <div>
            <div class="flex items-center justify-between">
              <label class="block text-sm font-medium">
                {{ t('KANBAN.FUNNELS.FORM.ACTIVE.LABEL') }}
              </label>
              <Switch v-model="formData.active" size="small" />
            </div>
            <p class="text-xs text-slate-500 dark:text-slate-400 mt-1 mb-4">
              {{ t('KANBAN.FUNNELS.FORM.ACTIVE.HELP') }}
            </p>
          </div>

          <!-- Nome do Funil -->
          <div>
            <label class="block text-sm font-medium mb-2">
              {{ t('KANBAN.FUNNELS.FORM.NAME.LABEL') }}
            </label>
            <input
              v-model="formData.name"
              type="text"
              class="w-full px-3 py-2 border rounded-lg"
              :placeholder="t('KANBAN.FUNNELS.FORM.NAME.PLACEHOLDER')"
              required
            />
          </div>

          <!-- Descrição -->
          <div>
            <label class="block text-sm font-medium mb-2">
              {{ t('KANBAN.FUNNELS.FORM.DESCRIPTION.LABEL') }}
            </label>
            <textarea
              v-model="formData.description"
              rows="3"
              class="w-full px-3 py-2 border rounded-lg"
              :placeholder="t('KANBAN.FUNNELS.FORM.DESCRIPTION.PLACEHOLDER')"
            />
          </div>

          <!-- Formulário Nova Etapa -->
          <div
            class="border border-slate-100 dark:border-slate-800 rounded-lg p-4 space-y-4"
            :class="{
              'border-2': editingStage,
            }"
            :style="editingStage ? { borderColor: newStage.color } : {}"
          >
            <h4 class="text-lg font-medium mb-4">
              <div class="flex items-center justify-between">
                <span>{{
                  editingStage
                    ? `${t('KANBAN.FUNNELS.FORM.STAGES.EDITING_TITLE')} ${newStage.name}`
                    : t('KANBAN.FUNNELS.FORM.STAGES.NEW_TITLE')
                }}</span>
                <span
                  v-if="editingStage"
                  class="text-sm px-2 py-1 rounded"
                  :style="{
                    backgroundColor: `${newStage.color}20`,
                    color: newStage.color,
                  }"
                >
                  {{ t('KANBAN.FUNNELS.FORM.STAGES.EDITING_BADGE') }}
                </span>
              </div>
            </h4>
            <!-- Nome da Etapa -->
            <div>
              <label class="block text-sm font-medium mb-2">
                {{ t('KANBAN.FUNNELS.FORM.STAGES.NAME_LABEL') }}
              </label>
              <input
                v-model="newStage.name"
                type="text"
                class="w-full px-3 py-2 border rounded-lg"
                :placeholder="t('KANBAN.FUNNELS.FORM.STAGES.NAME_PLACEHOLDER')"
              />
            </div>
            <!-- Cor e Descrição em flex -->
            <div class="flex items-start gap-2">
              <div class="w-[180px] shrink-0">
                <label class="block text-sm font-medium mb-2">
                  {{ t('KANBAN.FUNNELS.FORM.STAGES.COLOR_LABEL') }}
                </label>
                <StageColorPicker v-model="newStage.color" />
              </div>
              <div class="flex-1 min-w-0">
                <label class="block text-sm font-medium mb-2">
                  {{ t('KANBAN.FUNNELS.FORM.STAGES.DESCRIPTION_LABEL') }}
                </label>
                <input
                  v-model="newStage.description"
                  type="text"
                  class="w-full px-3 py-2 border rounded-lg"
                  :placeholder="
                    t(
                      'KANBAN.FUNNELS.FORM.STAGES.STAGE_DESCRIPTION_PLACEHOLDER'
                    )
                  "
                />
              </div>
            </div>
            <!-- Condições de Auto Criação -->
            <div class="mt-4">
              <label
                class="flex items-center justify-between text-sm font-medium mb-2"
              >
                <span>{{
                  t('KANBAN.FUNNELS.FORM.STAGES.AUTO_CREATE_CONDITIONS')
                }}</span>
                <div class="relative">
                  <span
                    class="text-xs text-slate-400 ml-1 cursor-help"
                    @mouseenter="showHelpPopover = true"
                    @mouseleave="showHelpPopover = false"
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
                      class="lucide lucide-info-icon lucide-info"
                    >
                      <circle cx="12" cy="12" r="10" />
                      <path d="M12 16v-4" />
                      <path d="M12 8h.01" />
                    </svg>
                  </span>
                  <div
                    v-show="showHelpPopover"
                    class="absolute right-0 top-full mt-2 w-80 p-3 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-lg text-xs text-slate-600 dark:text-slate-300 z-50"
                    @mouseenter="showHelpPopover = true"
                    @mouseleave="showHelpPopover = false"
                  >
                    <div
                      class="font-medium text-slate-700 dark:text-slate-200 mb-1"
                    >
                      {{ t('KANBAN.FUNNELS.FORM.AUTO_CREATION.HELP_TITLE') }}
                    </div>
                    <p class="leading-relaxed">
                      {{
                        t('KANBAN.FUNNELS.FORM.AUTO_CREATION.HELP_DESCRIPTION')
                      }}
                    </p>
                  </div>
                </div>
              </label>

              <!-- Lista de condições existentes -->
              <div
                v-if="newStage.auto_create_conditions.length > 0"
                class="mb-3 space-y-2"
              >
                <div
                  v-for="(condition, index) in newStage.auto_create_conditions"
                  :key="index"
                  class="flex items-center gap-2 p-2 bg-slate-50 dark:bg-slate-800 rounded border"
                >
                  <span
                    class="text-xs px-2 py-1 bg-woot-100 dark:bg-woot-900 text-woot-700 dark:text-woot-300 rounded"
                  >
                    {{ getConditionTypeLabel(condition.type) }}
                  </span>
                  <span
                    v-if="condition.attribute"
                    class="text-xs text-slate-600 dark:text-slate-400"
                  >
                    {{ condition.attribute }}
                  </span>
                  <span
                    v-if="
                      condition.operator &&
                      condition.type === 'contact_has_custom_attribute'
                    "
                    class="text-xs text-slate-600 dark:text-slate-400"
                  >
                    {{ getOperatorLabel(condition.operator) }}
                  </span>
                  <span class="text-xs font-medium">{{ condition.value }}</span>
                  <button
                    type="button"
                    class="ml-auto text-ruby-500 hover:text-ruby-600"
                    @click="removeCondition(index)"
                  >
                    ✕
                  </button>
                </div>
              </div>

              <!-- Formulário para adicionar nova condição -->
              <div class="flex items-center gap-2">
                <select
                  v-model="newCondition.type"
                  class="px-2 py-1 border rounded text-sm w-40 h-10 align-middle"
                >
                  <option value="contact_has_tag">
                    {{
                      t('KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.CONTACT_HAS_TAG')
                    }}
                  </option>
                  <option value="contact_has_custom_attribute">
                    {{
                      t(
                        'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.CONTACT_HAS_CUSTOM_ATTRIBUTE'
                      )
                    }}
                  </option>
                  <option value="message_contains">
                    {{
                      t(
                        'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.MESSAGE_CONTAINS'
                      )
                    }}
                  </option>
                  <option value="conversation_has_priority">
                    {{
                      t(
                        'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.CONVERSATION_HAS_PRIORITY'
                      )
                    }}
                  </option>
                  <option value="inbox_matches">
                    {{
                      t('KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.INBOX_MATCHES')
                    }}
                  </option>
                  <option value="message_is_private">
                    {{
                      t(
                        'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.MESSAGE_IS_PRIVATE'
                      )
                    }}
                  </option>
                  <option value="message_has_automation">
                    {{
                      t(
                        'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.MESSAGE_HAS_AUTOMATION'
                      )
                    }}
                  </option>
                  <option value="conversation_message_count">
                    {{
                      t(
                        'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.CONVERSATION_MESSAGE_COUNT'
                      )
                    }}
                  </option>
                  <option value="last_message_age">
                    {{
                      t(
                        'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.LAST_MESSAGE_AGE'
                      )
                    }}
                  </option>
                  <option value="message_not_read">
                    {{
                      t(
                        'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.MESSAGE_NOT_READ'
                      )
                    }}
                  </option>
                  <option value="conversation_unassigned">
                    {{
                      t(
                        'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.CONVERSATION_UNASSIGNED'
                      )
                    }}
                  </option>
                  <option value="conversation_reopened">
                    {{
                      t(
                        'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.CONVERSATION_REOPENED'
                      )
                    }}
                  </option>
                  <option value="conversation_snoozed">
                    {{
                      t(
                        'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.CONVERSATION_SNOOZED'
                      )
                    }}
                  </option>
                </select>
                <input
                  v-if="newCondition.type === 'contact_has_custom_attribute'"
                  v-model="newCondition.attribute"
                  type="text"
                  :placeholder="
                    t(
                      'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.ATTRIBUTE_PLACEHOLDER'
                    )
                  "
                  class="px-2 py-1 border rounded text-sm w-40 h-10 align-middle"
                />
                <select
                  v-if="
                    newCondition.type === 'conversation_message_count' ||
                    newCondition.type === 'last_message_age'
                  "
                  v-model="newCondition.operator"
                  class="px-2 py-1 border rounded text-sm w-40 h-10 align-middle"
                >
                  <option value="equal_to">
                    {{ getOperatorLabel('equal_to') }}
                  </option>
                  <option value="greater_than">
                    {{ getOperatorLabel('greater_than') }}
                  </option>
                  <option value="less_than">
                    {{ getOperatorLabel('less_than') }}
                  </option>
                  <option value="greater_than_or_equal">
                    {{ getOperatorLabel('greater_than_or_equal') }}
                  </option>
                  <option value="less_than_or_equal">
                    {{ getOperatorLabel('less_than_or_equal') }}
                  </option>
                </select>
                <select
                  v-if="newCondition.type === 'contact_has_custom_attribute'"
                  v-model="newCondition.operator"
                  class="px-2 py-1 border rounded text-sm w-40 h-10 align-middle"
                >
                  <option value="equal_to">
                    {{ getOperatorLabel('equal_to') }}
                  </option>
                  <option value="contains">
                    {{ getOperatorLabel('contains') }}
                  </option>
                  <option value="not_equal_to">
                    {{ getOperatorLabel('not_equal_to') }}
                  </option>
                </select>
                <input
                  v-if="
                    newCondition.type !== 'inbox_matches' &&
                    newCondition.type !== 'message_not_read' &&
                    newCondition.type !== 'conversation_unassigned' &&
                    newCondition.type !== 'conversation_reopened' &&
                    newCondition.type !== 'conversation_snoozed'
                  "
                  v-model="newCondition.value"
                  :type="
                    newCondition.type === 'conversation_message_count' ||
                    newCondition.type === 'last_message_age'
                      ? 'number'
                      : 'text'
                  "
                  :placeholder="
                    newCondition.type === 'contact_has_tag'
                      ? t(
                          'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.TAG_PLACEHOLDER'
                        )
                      : newCondition.type === 'message_contains'
                        ? t(
                            'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.TEXT_PLACEHOLDER'
                          )
                        : newCondition.type === 'message_is_private'
                          ? t(
                              'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.PRIVATE_MESSAGE_PLACEHOLDER'
                            )
                          : newCondition.type === 'message_has_automation'
                            ? t(
                                'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.AUTOMATION_MESSAGE_PLACEHOLDER'
                              )
                            : newCondition.type === 'conversation_has_priority'
                              ? t(
                                  'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.PRIORITY_PLACEHOLDER'
                                )
                              : newCondition.type ===
                                  'conversation_message_count'
                                ? t(
                                    'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.QUANTITY_PLACEHOLDER'
                                  )
                                : newCondition.type === 'last_message_age'
                                  ? t(
                                      'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.MINUTES_PLACEHOLDER'
                                    )
                                  : t(
                                      'KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.VALUE_PLACEHOLDER'
                                    )
                  "
                  class="px-2 py-1 border rounded text-sm w-40 h-10 align-middle"
                />
                <select
                  v-else
                  v-model="newCondition.value"
                  class="w-full px-3 py-2 border rounded-lg text-sm"
                >
                  <option value="">
                    {{
                      t('KANBAN.FUNNELS.FORM.STAGES.CONDITIONS.SELECT_INBOX')
                    }}
                  </option>
                  <option
                    v-for="inbox in inboxes"
                    :key="inbox.id"
                    :value="inbox.id"
                  >
                    {{ inbox.name }} ({{
                      inbox.channel_type.replace('Channel::', '')
                    }})
                  </option>
                </select>
                <Button
                  color="blue"
                  size="sm"
                  :disabled="!canAddCondition"
                  class="ml-2 flex items-center justify-center p-0 align-middle !h-10 !w-10 !min-w-[40px]"
                  style="
                    height: 38px;
                    width: 40px;
                    min-width: 40px;
                    margin-top: -9px;
                  "
                  @click="addCondition"
                >
                  <template #icon>
                    <fluent-icon icon="add" size="18" />
                  </template>
                </Button>
              </div>
            </div>

            <div class="flex justify-end">
              <Button
                variant="solid"
                color="blue"
                size="sm"
                :disabled="!newStage.name"
                :label="
                  editingStage
                    ? t('KANBAN.FUNNELS.FORM.STAGES.SAVE_BUTTON')
                    : t('KANBAN.FUNNELS.FORM.STAGES.ADD_BUTTON')
                "
                @click.stop="handleAddStage"
              />
            </div>
          </div>
        </div>
        <!-- Fim do conteúdo colapsável -->

        <!-- Campos Personalizados Globais - Grupo Colapse -->
        <div
          class="flex items-center justify-between mb-4"
          style="margin-top: 16px"
        >
          <div class="flex items-center gap-2 text-base font-medium">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="lucide lucide-list-plus-icon lucide-list-plus"
            >
              <path d="M16 5H3" />
              <path d="M11 12H3" />
              <path d="M16 19H3" />
              <path d="M18 9v6" />
              <path d="M21 12h-6" />
            </svg>
            {{ t('KANBAN.FUNNELS.FORM.SECTIONS.GLOBAL_CUSTOM_FIELDS') }}
          </div>
          <div class="flex-1 mx-4 h-px bg-slate-200 dark:bg-slate-700" />
          <button
            type="button"
            class="flex items-center justify-center w-8 h-8 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800"
            @click="toggleGlobalFields"
          >
            <fluent-icon
              :icon="globalFieldsCollapsed ? 'chevron-down' : 'chevron-up'"
              size="16"
            />
          </button>
        </div>

        <!-- Conteúdo colapsável dos campos globais -->
        <div v-show="!globalFieldsCollapsed">
          <div
            class="border border-slate-100 dark:border-slate-800 rounded-lg p-4 space-y-4"
          >
            <div class="space-y-4">
              <div
                v-for="(attr, idx) in globalCustomAttributes || []"
                :key="idx"
                class="border border-slate-200 dark:border-slate-700 rounded-lg p-3 space-y-2"
              >
                <div class="flex gap-2 items-center">
                  <input
                    v-model="attr.name"
                    type="text"
                    class="w-1/2 rounded-lg"
                    placeholder="Chave (name)"
                  />
                  <select v-model="attr.type" class="w-1/2 rounded-lg">
                    <option value="" disabled selected>Tipo</option>
                    <option value="string">Texto</option>
                    <option value="number">Número</option>
                    <option value="date">Data</option>
                    <option value="boolean">Verdadeiro/Falso</option>
                  </select>
                  <select
                    v-model="attr.field_type"
                    class="px-2 py-1 border rounded text-sm w-36 h-10 align-middle"
                  >
                    <option value="single">Único</option>
                    <option value="list">Lista</option>
                  </select>
                  <button
                    type="button"
                    class="p-1 text-ruby-500"
                    @click="removeGlobalCustomAttribute(idx)"
                  >
                    ✕
                  </button>
                </div>

                <!-- Input para valores da lista -->
                <div v-if="attr.field_type === 'list'" class="pl-2 space-y-2">
                  <label
                    class="text-xs font-medium text-slate-600 dark:text-slate-400"
                    >Valores da lista:</label>
                  <div
                    v-for="(value, valueIdx) in attr.list_values || []"
                    :key="valueIdx"
                    class="flex gap-2 items-center"
                  >
                    <input
                      v-model="attr.list_values[valueIdx]"
                      type="text"
                      class="flex-1 px-2 py-1 border rounded text-sm"
                      placeholder="Valor"
                    />
                    <button
                      type="button"
                      class="text-ruby-500 text-sm"
                      @click="removeListValue(idx, valueIdx)"
                    >
                      ✕
                    </button>
                  </div>
                  <button
                    type="button"
                    class="text-xs px-2 py-1 bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300 rounded hover:bg-slate-200 dark:hover:bg-slate-600"
                    @click="addListValue(idx)"
                  >
                    + Adicionar valor
                  </button>
                </div>
              </div>
              <button
                type="button"
                class="mt-2 px-3 py-1 bg-woot-500 text-white rounded"
                @click="addGlobalCustomAttribute"
              >
                Adicionar campo
              </button>
            </div>
          </div>
        </div>

        <!-- Metas - Grupo Colapse -->
        <div
          class="flex items-center justify-between mb-4"
          style="margin-top: 16px"
        >
          <div class="flex items-center gap-2 text-base font-medium">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="lucide lucide-crosshair-icon lucide-crosshair"
            >
              <circle cx="12" cy="12" r="10" />
              <line x1="22" x2="18" y1="12" y2="12" />
              <line x1="6" x2="2" y1="12" y2="12" />
              <line x1="12" x2="12" y1="6" y2="2" />
              <line x1="12" x2="12" y1="22" y2="18" />
            </svg>
            {{ t('KANBAN.FUNNELS.FORM.SECTIONS.GOALS') }}
          </div>
          <div class="flex-1 mx-4 h-px bg-slate-200 dark:bg-slate-700" />
          <button
            type="button"
            class="flex items-center justify-center w-8 h-8 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800"
            @click="toggleGoals"
          >
            <fluent-icon
              :icon="goalsCollapsed ? 'chevron-down' : 'chevron-up'"
              size="16"
            />
          </button>
        </div>

        <!-- Conteúdo colapsável das metas -->
        <div v-show="!goalsCollapsed">
          <!-- Formulário Nova Meta -->
          <div
            class="border border-slate-100 dark:border-slate-800 rounded-lg p-4 space-y-4"
            :class="{
              'border-2': editingGoal,
            }"
            :style="editingGoal ? { borderColor: '#3B82F6' } : {}"
          >
            <h4 class="text-lg font-medium mb-4">
              <div class="flex items-center justify-between">
                <span>{{
                  editingGoal
                    ? `${t('KANBAN.FUNNELS.FORM.GOALS.EDITING_TITLE')} ${getGoalTypeLabel(editingGoal.type)}`
                    : t('KANBAN.FUNNELS.FORM.GOALS.NEW_TITLE')
                }}</span>
                <span
                  v-if="editingGoal"
                  class="text-sm px-2 py-1 rounded"
                  style="background-color: #3b82f620; color: #3b82f6"
                >
                  {{ t('KANBAN.FUNNELS.FORM.GOALS.EDITING_BADGE') }}
                </span>
              </div>
            </h4>

            <!-- Seleção do Tipo de Meta -->
            <div>
              <label class="block text-sm font-medium mb-2">{{
                t('KANBAN.FUNNELS.FORM.GOALS.TYPE_LABEL')
              }}</label>
              <div class="flex flex-wrap gap-2">
                <button
                  v-for="(type, key) in {
                    conversion_rate: {
                      label: t(
                        'KANBAN.FUNNELS.FORM.GOALS.TYPES.CONVERSION_RATE'
                      ),
                      color: '#3B82F6',
                    },
                    average_value: {
                      label: t('KANBAN.FUNNELS.FORM.GOALS.TYPES.AVERAGE_VALUE'),
                      color: '#10B981',
                    },
                    average_time: {
                      label: t('KANBAN.FUNNELS.FORM.GOALS.TYPES.AVERAGE_TIME'),
                      color: '#F59E0B',
                    },
                    total_conversions: {
                      label: t(
                        'KANBAN.FUNNELS.FORM.GOALS.TYPES.TOTAL_CONVERSIONS'
                      ),
                      color: '#8B5CF6',
                    },
                    total_revenue: {
                      label: t('KANBAN.FUNNELS.FORM.GOALS.TYPES.TOTAL_REVENUE'),
                      color: '#EF4444',
                    },
                  }"
                  :key="key"
                  type="button"
                  class="flex items-center gap-2 px-3 py-2 rounded-lg border transition-colors"
                  :style="
                    newGoal.type === key
                      ? {
                          borderColor: type.color,
                          backgroundColor: type.color + '80',
                          color: type.color,
                        }
                      : {
                          borderColor: type.color,
                          backgroundColor: 'transparent',
                          color: type.color,
                        }
                  "
                  @click="newGoal.type = key"
                >
                  <span class="text-sm">{{ type.label }}</span>
                </button>
              </div>
            </div>

            <!-- Valor da Meta -->
            <div>
              <label class="block text-sm font-medium mb-2">{{
                t('KANBAN.FUNNELS.FORM.GOALS.VALUE_LABEL')
              }}</label>
              <div class="flex items-center gap-2">
                <input
                  v-model="newGoal.value"
                  :type="
                    ['percentage', 'currency', 'count'].includes(newGoal.unit)
                      ? 'number'
                      : 'text'
                  "
                  class="w-full px-3 py-2 border rounded-lg"
                  :placeholder="
                    newGoal.type === 'conversion_rate'
                      ? t(
                          'KANBAN.FUNNELS.FORM.GOALS.VALUE_PLACEHOLDER.CONVERSION_RATE'
                        )
                      : newGoal.type === 'average_value'
                        ? t(
                            'KANBAN.FUNNELS.FORM.GOALS.VALUE_PLACEHOLDER.AVERAGE_VALUE'
                          )
                        : newGoal.type === 'average_time'
                          ? t(
                              'KANBAN.FUNNELS.FORM.GOALS.VALUE_PLACEHOLDER.AVERAGE_TIME'
                            )
                          : t(
                              'KANBAN.FUNNELS.FORM.GOALS.VALUE_PLACEHOLDER.DEFAULT'
                            )
                  "
                />
                <span class="text-sm text-slate-500 px-2">{{
                  getUnitLabel(newGoal.unit)
                }}</span>
              </div>
            </div>

            <!-- Descrição -->
            <div>
              <label class="block text-sm font-medium mb-2">{{
                t('KANBAN.FUNNELS.FORM.GOALS.DESCRIPTION_LABEL')
              }}</label>
              <input
                v-model="newGoal.description"
                type="text"
                class="w-full px-3 py-2 border rounded-lg"
                :placeholder="
                  t('KANBAN.FUNNELS.FORM.GOALS.DESCRIPTION_PLACEHOLDER')
                "
              />
            </div>

            <div class="flex justify-end gap-2">
              <Button
                v-if="editingGoal"
                variant="outline"
                color="slate"
                size="sm"
                :label="t('KANBAN.FUNNELS.FORM.ACTIONS.CANCEL')"
                @click="cancelEditingGoal"
              />
              <Button
                variant="solid"
                color="blue"
                size="sm"
                :disabled="!newGoal.value"
                :label="
                  editingGoal
                    ? t('KANBAN.FUNNELS.FORM.ACTIONS.SAVE')
                    : t('KANBAN.FUNNELS.FORM.GOALS.ADD_BUTTON')
                "
                @click="addGoal"
              />
            </div>
          </div>

          <!-- Lista de Metas Configuradas -->
          <div v-if="goals.length > 0" class="mt-4 space-y-2">
            <h4
              class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-3"
            >
              {{ t('KANBAN.FUNNELS.FORM.GOALS.CONFIGURED_TITLE') }}
            </h4>
            <div
              v-for="(goal, index) in goals"
              :key="goal.id"
              class="flex items-center justify-between p-3 bg-slate-50 dark:bg-slate-800 rounded-lg border border-slate-100 dark:border-slate-700"
            >
              <div class="flex items-center gap-3">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium">{{
                    getGoalTypeLabel(goal.type)
                  }}</span>
                </div>
                <div class="flex items-center gap-1">
                  <span
                    class="text-sm font-medium text-blue-600 dark:text-blue-400"
                    >{{ goal.value }}</span>
                  <span class="text-xs text-slate-500">{{
                    getUnitLabel(goal.unit)
                  }}</span>
                </div>
                <div
                  v-if="goal.description"
                  class="text-xs text-slate-500 italic"
                >
                  {{ goal.description }}
                </div>
              </div>
              <div class="flex items-center gap-1">
                <button
                  type="button"
                  class="text-slate-400 hover:text-slate-500 p-1"
                  @click="startEditingGoal(goal)"
                >
                  <fluent-icon icon="edit" size="14" />
                </button>
                <button
                  type="button"
                  class="text-slate-400 hover:text-slate-500 p-1"
                  @click="removeGoal(index)"
                >
                  <fluent-icon icon="delete" size="14" />
                </button>
              </div>
            </div>
          </div>

          <!-- Estado vazio -->
          <div v-else class="mt-4 text-center py-8 text-slate-400">
            <p class="text-sm">
              {{ t('KANBAN.FUNNELS.FORM.GOALS.EMPTY_STATE') }}
            </p>
            <p class="text-xs">
              {{ t('KANBAN.FUNNELS.FORM.GOALS.EMPTY_DESCRIPTION') }}
            </p>
          </div>
        </div>

        <!-- Motivos de Perda e Ganho - Grupo Colapse -->
        <div
          class="flex items-center justify-between mb-4"
          style="margin-top: 16px"
        >
          <div class="flex items-center gap-2 text-base font-medium">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="lucide lucide-list-checks-icon lucide-list-checks"
            >
              <path d="M3 17h2" />
              <path d="M3 7h2" />
              <path d="M3 12h2" />
              <path d="M9 7l2 2 4-4" />
              <path d="M9 17l2 2 4-4" />
              <path d="M9 12h12" />
            </svg>
            {{ t('KANBAN.FUNNELS.FORM.SECTIONS.LOSS_WIN_REASONS') }}
          </div>
          <div class="flex-1 mx-4 h-px bg-slate-200 dark:bg-slate-700" />
          <button
            type="button"
            class="flex items-center justify-center w-8 h-8 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800"
            @click="toggleLossWinReasons"
          >
            <fluent-icon
              :icon="lossWinReasonsCollapsed ? 'chevron-down' : 'chevron-up'"
              size="16"
            />
          </button>
        </div>

        <!-- Conteúdo colapsável dos motivos -->
        <div v-show="!lossWinReasonsCollapsed">
          <!-- Formulário Novo Motivo -->
          <div
            class="border border-slate-100 dark:border-slate-800 rounded-lg p-4 space-y-4"
            :class="{
              'border-2': editingReason,
            }"
            :style="
              editingReason
                ? {
                    borderColor:
                      newReason.type === 'loss' ? '#E11D48' : '#14B8A6',
                  }
                : {}
            "
          >
            <h4 class="text-lg font-medium mb-4">
              <div class="flex items-center justify-between">
                <span>{{
                  editingReason
                    ? t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.EDITING_TITLE')
                    : t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.NEW_TITLE')
                }}</span>
                <span
                  v-if="editingReason"
                  class="text-sm px-2 py-1 rounded"
                  :style="{
                    backgroundColor:
                      newReason.type === 'loss' ? '#E11D4820' : '#14B8A620',
                    color: newReason.type === 'loss' ? '#E11D48' : '#14B8A6',
                  }"
                >
                  {{ t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.EDITING_BADGE') }}
                </span>
              </div>
            </h4>

            <!-- Seleção do Tipo -->
            <div>
              <label class="block text-sm font-medium mb-2">{{
                t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.TYPE_LABEL')
              }}</label>
              <div class="flex gap-2">
                <button
                  type="button"
                  class="flex-1 flex items-center justify-center gap-2 px-4 py-2 rounded-lg border-2 transition-colors"
                  :style="
                    newReason.type === 'loss'
                      ? {
                          borderColor: '#E11D48',
                          backgroundColor: '#FFF1F2',
                          color: '#E11D48',
                        }
                      : {
                          borderColor: '#E2E8F0',
                          backgroundColor: 'transparent',
                          color: '#64748B',
                        }
                  "
                  @click="newReason.type = 'loss'"
                >
                  <span class="text-sm font-medium">{{
                    t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.TYPE_LOSS')
                  }}</span>
                </button>
                <button
                  type="button"
                  class="flex-1 flex items-center justify-center gap-2 px-4 py-2 rounded-lg border-2 transition-colors"
                  :style="
                    newReason.type === 'win'
                      ? {
                          borderColor: '#14B8A6',
                          backgroundColor: '#F0FDFA',
                          color: '#14B8A6',
                        }
                      : {
                          borderColor: '#E2E8F0',
                          backgroundColor: 'transparent',
                          color: '#64748B',
                        }
                  "
                  @click="newReason.type = 'win'"
                >
                  <span class="text-sm font-medium">{{
                    t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.TYPE_WIN')
                  }}</span>
                </button>
              </div>
            </div>

            <!-- Título do Motivo -->
            <div>
              <label class="block text-sm font-medium mb-2">{{
                t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.TITLE_LABEL')
              }}</label>
              <input
                v-model="newReason.title"
                type="text"
                class="w-full px-3 py-2 border rounded-lg"
                :placeholder="
                  t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.TITLE_PLACEHOLDER')
                "
              />
            </div>

            <!-- Descrição -->
            <div>
              <label class="block text-sm font-medium mb-2">{{
                t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.DESCRIPTION_LABEL')
              }}</label>
              <textarea
                v-model="newReason.description"
                rows="2"
                class="w-full px-3 py-2 border rounded-lg"
                :placeholder="
                  t(
                    'KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.DESCRIPTION_PLACEHOLDER'
                  )
                "
              />
            </div>

            <div class="flex justify-end gap-2">
              <Button
                v-if="editingReason"
                variant="outline"
                color="slate"
                size="sm"
                :label="t('KANBAN.FUNNELS.FORM.ACTIONS.CANCEL')"
                @click="cancelEditingReason"
              />
              <Button
                variant="solid"
                :color="newReason.type === 'loss' ? 'ruby' : 'teal'"
                size="sm"
                :disabled="!newReason.title.trim()"
                :label="
                  editingReason
                    ? t('KANBAN.FUNNELS.FORM.ACTIONS.SAVE')
                    : t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.ADD_BUTTON')
                "
                @click="addReason"
              />
            </div>
          </div>

          <!-- Listas de Motivos -->
          <div class="mt-4 grid grid-cols-2 gap-4">
            <!-- Motivos de Perda -->
            <div>
              <h4
                class="text-sm font-medium text-ruby-700 dark:text-ruby-300 mb-3 flex items-center gap-2"
              >
                <span>{{
                  t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.LOSS_REASONS_TITLE')
                }}</span>
                <span
                  class="px-2 py-0.5 text-xs bg-ruby-100 dark:bg-ruby-900/20 rounded-full"
                  >{{ lossReasons.length }}</span>
              </h4>
              <div v-if="lossReasons.length > 0" class="space-y-2">
                <div
                  v-for="(reason, index) in lossReasons"
                  :key="reason.id"
                  class="p-3 bg-ruby-50 dark:bg-ruby-900/10 rounded-lg border border-ruby-100 dark:border-ruby-800"
                >
                  <div class="flex items-start justify-between mb-1">
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                      >{{ reason.title }}</span>
                    <div class="flex items-center gap-1">
                      <button
                        type="button"
                        class="text-slate-400 hover:text-slate-500 p-1"
                        @click="startEditingReason('loss', reason)"
                      >
                        <fluent-icon icon="edit" size="14" />
                      </button>
                      <button
                        type="button"
                        class="text-slate-400 hover:text-slate-500 p-1"
                        @click="removeReason('loss', index)"
                      >
                        <fluent-icon icon="delete" size="14" />
                      </button>
                    </div>
                  </div>
                  <p
                    v-if="reason.description"
                    class="text-xs text-slate-500 dark:text-slate-400"
                  >
                    {{ reason.description }}
                  </p>
                </div>
              </div>
              <div v-else class="text-center py-4 text-slate-400">
                <p class="text-xs">
                  {{ t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.EMPTY_LOSS') }}
                </p>
              </div>
            </div>

            <!-- Motivos de Ganho -->
            <div>
              <h4
                class="text-sm font-medium text-teal-700 dark:text-teal-300 mb-3 flex items-center gap-2"
              >
                <span>{{
                  t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.WIN_REASONS_TITLE')
                }}</span>
                <span
                  class="px-2 py-0.5 text-xs bg-teal-100 dark:bg-teal-900/20 rounded-full"
                  >{{ winReasons.length }}</span>
              </h4>
              <div v-if="winReasons.length > 0" class="space-y-2">
                <div
                  v-for="(reason, index) in winReasons"
                  :key="reason.id"
                  class="p-3 bg-teal-50 dark:bg-teal-900/10 rounded-lg border border-teal-100 dark:border-teal-800"
                >
                  <div class="flex items-start justify-between mb-1">
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                      >{{ reason.title }}</span>
                    <div class="flex items-center gap-1">
                      <button
                        type="button"
                        class="text-slate-400 hover:text-slate-500 p-1"
                        @click="startEditingReason('win', reason)"
                      >
                        <fluent-icon icon="edit" size="14" />
                      </button>
                      <button
                        type="button"
                        class="text-slate-400 hover:text-slate-500 p-1"
                        @click="removeReason('win', index)"
                      >
                        <fluent-icon icon="delete" size="14" />
                      </button>
                    </div>
                  </div>
                  <p
                    v-if="reason.description"
                    class="text-xs text-slate-500 dark:text-slate-400"
                  >
                    {{ reason.description }}
                  </p>
                </div>
              </div>
              <div v-else class="text-center py-4 text-slate-400">
                <p class="text-xs">
                  {{ t('KANBAN.FUNNELS.FORM.LOSS_WIN_REASONS.EMPTY_WIN') }}
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Checklist Presets - Grupo Colapse -->
        <div
          class="flex items-center justify-between mb-4"
          style="margin-top: 16px"
        >
          <div class="flex items-center gap-2 text-base font-medium">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="lucide lucide-list-check-icon lucide-list-check"
            >
              <path d="M16 5H3" />
              <path d="M16 12H3" />
              <path d="M11 19H3" />
              <path d="m15 18 2 2 4-4" />
            </svg>
            {{ t('KANBAN.FUNNELS.FORM.SECTIONS.CHECKLIST_PRESETS') }}
          </div>
          <div class="flex-1 mx-4 h-px bg-slate-200 dark:bg-slate-700" />
          <button
            type="button"
            class="flex items-center justify-center w-8 h-8 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800"
            @click="toggleChecklistPresets"
          >
            <fluent-icon
              :icon="checklistPresetsCollapsed ? 'chevron-down' : 'chevron-up'"
              size="16"
            />
          </button>
        </div>

        <!-- Conteúdo colapsável dos checklist presets -->
        <div v-show="!checklistPresetsCollapsed">
          <!-- Seleção de etapa -->
          <div class="mb-4">
            <label class="block text-sm font-medium mb-2">
              {{ t('KANBAN.FUNNELS.FORM.CHECKLIST_PRESETS.SELECT_STAGE') }}
            </label>
            <select
              v-model="selectedStageForChecklist"
              class="w-full px-3 py-2 border rounded-lg"
            >
              <option :value="null">
                {{
                  t(
                    'KANBAN.FUNNELS.FORM.CHECKLIST_PRESETS.SELECT_STAGE_PLACEHOLDER'
                  )
                }}
              </option>
              <option v-for="stage in stages" :key="stage.id" :value="stage.id">
                {{ stage.name }}
              </option>
            </select>
          </div>

          <!-- Formulário para adicionar novo item -->
          <div
            v-if="selectedStageForChecklist"
            class="border border-slate-100 dark:border-slate-800 rounded-lg p-4 space-y-4"
            :class="{
              'border-2': editingChecklistItem,
            }"
            :style="editingChecklistItem ? { borderColor: '#3B82F6' } : {}"
          >
            <h4 class="text-lg font-medium mb-4">
              <div class="flex items-center justify-between">
                <span>{{
                  editingChecklistItem
                    ? t('KANBAN.FUNNELS.FORM.CHECKLIST_PRESETS.EDITING_TITLE')
                    : t('KANBAN.FUNNELS.FORM.CHECKLIST_PRESETS.NEW_TITLE')
                }}</span>
                <span
                  v-if="editingChecklistItem"
                  class="text-sm px-2 py-1 rounded"
                  style="background-color: #3b82f620; color: #3b82f6"
                >
                  {{ t('KANBAN.FUNNELS.FORM.CHECKLIST_PRESETS.EDITING_BADGE') }}
                </span>
              </div>
            </h4>

            <!-- Texto do item -->
            <div>
              <label class="block text-sm font-medium mb-2">{{
                t('KANBAN.FUNNELS.FORM.CHECKLIST_PRESETS.TEXT_LABEL')
              }}</label>
              <textarea
                v-model="newChecklistItem.text"
                rows="3"
                class="w-full px-3 py-2 border rounded-lg"
                :placeholder="
                  t('KANBAN.FUNNELS.FORM.CHECKLIST_PRESETS.TEXT_PLACEHOLDER')
                "
              />
            </div>

            <!-- Prioridade -->
            <div>
              <label class="block text-sm font-medium mb-2">{{
                t('KANBAN.FUNNELS.FORM.CHECKLIST_PRESETS.PRIORITY_LABEL')
              }}</label>
              <select
                v-model="newChecklistItem.priority"
                class="w-full px-3 py-2 border rounded-lg text-sm"
              >
                <option value="none">Nenhuma</option>
                <option value="low">Baixa</option>
                <option value="medium">Média</option>
                <option value="high">Alta</option>
                <option value="urgent">Urgente</option>
              </select>
            </div>

            <!-- Obrigatório -->
            <div>
              <div class="flex items-center justify-between">
                <label class="block text-sm font-medium"> Obrigatório </label>
                <Switch v-model="newChecklistItem.required" size="small" />
              </div>
              <p class="text-xs text-slate-500 dark:text-slate-400 mt-1">
                Marque se este item deve ser obrigatoriamente concluído
              </p>
            </div>

            <div class="flex justify-end gap-2">
              <Button
                v-if="editingChecklistItem"
                variant="outline"
                color="slate"
                size="sm"
                :label="t('KANBAN.FUNNELS.FORM.ACTIONS.CANCEL')"
                @click="cancelEditingChecklistPreset"
              />
              <Button
                variant="solid"
                color="blue"
                size="sm"
                :disabled="!newChecklistItem.text.trim()"
                :label="
                  editingChecklistItem
                    ? t('KANBAN.FUNNELS.FORM.ACTIONS.SAVE')
                    : t('KANBAN.FUNNELS.FORM.CHECKLIST_PRESETS.ADD_BUTTON')
                "
                @click="addChecklistPreset"
              />
            </div>
          </div>

          <!-- Lista de checklist presets por etapa -->
          <div v-if="selectedStageForChecklist" class="mt-4">
            <div
              v-for="stage in stages.filter(
                s => s.id === selectedStageForChecklist
              )"
              :key="stage.id"
            >
              <h4
                class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-3 flex items-center gap-2"
              >
                <div
                  class="w-2.5 h-2.5 rounded-full"
                  :style="{ backgroundColor: stage.color }"
                />
                <span>{{ stage.name }}</span>
                <span
                  class="px-2 py-0.5 text-xs bg-slate-100 dark:bg-slate-800 rounded-full"
                >
                  {{ (stage.checklist_templates || []).length }}
                </span>
              </h4>
              <div
                v-if="(stage.checklist_templates || []).length > 0"
                class="space-y-2"
              >
                <div
                  v-for="(item, index) in stage.checklist_templates"
                  :key="item.id"
                  class="p-3 bg-slate-50 dark:bg-slate-800 rounded-lg border border-slate-100 dark:border-slate-700"
                >
                  <div class="flex items-start justify-between mb-1">
                    <span
                      class="text-sm text-slate-700 dark:text-slate-300 flex-1"
                      >{{ item.text }}</span>
                    <div class="flex items-center gap-1">
                      <button
                        type="button"
                        class="text-slate-400 hover:text-slate-500 p-1"
                        @click="startEditingChecklistPreset(item)"
                      >
                        <fluent-icon icon="edit" size="14" />
                      </button>
                      <button
                        type="button"
                        class="text-slate-400 hover:text-slate-500 p-1"
                        @click="removeChecklistPreset(stage.id, index)"
                      >
                        <fluent-icon icon="delete" size="14" />
                      </button>
                    </div>
                  </div>
                  <div
                    v-if="item.priority !== 'none' || item.required"
                    class="mt-2 flex items-center gap-2"
                  >
                    <span
                      v-if="item.priority !== 'none'"
                      class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-full"
                      :class="{
                        'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300':
                          getChecklistPresetPriority(item.priority).color ===
                          'red',
                        'bg-orange-100 dark:bg-orange-900/30 text-orange-700 dark:text-orange-300':
                          getChecklistPresetPriority(item.priority).color ===
                          'orange',
                        'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-300':
                          getChecklistPresetPriority(item.priority).color ===
                          'yellow',
                        'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300':
                          getChecklistPresetPriority(item.priority).color ===
                          'green',
                      }"
                    >
                      {{ getChecklistPresetPriority(item.priority).label }}
                    </span>
                    <span
                      v-if="item.required"
                      class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-full bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300"
                    >
                      Obrigatório
                    </span>
                  </div>
                </div>
              </div>
              <div v-else class="text-center py-4 text-slate-400">
                <p class="text-xs">
                  {{ t('KANBAN.FUNNELS.FORM.CHECKLIST_PRESETS.EMPTY_STATE') }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Coluna Direita - Lista de Etapas -->
      <div class="space-y-6">
        <div>
          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-2 text-sm font-medium">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="lucide lucide-columns3-icon lucide-columns-3"
              >
                <rect width="18" height="18" x="3" y="3" rx="2" />
                <path d="M9 3v18" />
                <path d="M15 3v18" />
              </svg>
              <span>{{ t('KANBAN.FUNNELS.FORM.SECTIONS.FUNNEL_STAGES') }}</span>
            </div>
            <div class="flex items-center gap-2">
              <span
                class="px-2 py-1 text-xs bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 rounded-full"
              >
                {{ stages.length }}
              </span>
              <button
                type="button"
                class="flex items-center justify-center w-8 h-8 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800"
                @click="toggleStages"
              >
                <fluent-icon
                  :icon="stagesCollapsed ? 'chevron-down' : 'chevron-up'"
                  size="16"
                />
              </button>
            </div>
          </div>

          <!-- Lista de Etapas -->
          <div v-show="!stagesCollapsed" class="space-y-2">
            <draggable
              v-model="stages"
              :options="dragOptions"
              item-key="id"
              class="space-y-2"
              @change="handleOrderChange"
            >
              <template #item="{ element: stage, index }">
                <div
                  class="stage-preview-card flex flex-col border border-slate-100 dark:border-slate-800 rounded-lg cursor-move group transition-colors duration-200 bg-slate-100 dark:bg-slate-800"
                  :style="
                    stage._hover
                      ? {
                          background: `linear-gradient(90deg, ${stage.color}22 0%, transparent 100%)`,
                        }
                      : {}
                  "
                  @mouseenter="stage._hover = true"
                  @mouseleave="stage._hover = false"
                >
                  <div class="flex items-center gap-2 p-2 select-none">
                    <div
                      class="w-2.5 h-2.5 rounded-full"
                      :style="{ backgroundColor: stage.color }"
                    />
                    <div
                      class="text-sm font-medium flex-1 truncate"
                      :title="stage.name"
                    >
                      {{
                        stage.name.length > 25
                          ? stage.name.slice(0, 25) + '…'
                          : stage.name
                      }}
                    </div>
                    <div class="flex items-center gap-2">
                      <div class="relative">
                        <button
                          type="button"
                          class="text-slate-400 hover:text-slate-500 p-0 m-0"
                          @click.stop="copyStageId(stage.id)"
                        >
                          <fluent-icon icon="copy" size="14" />
                        </button>
                        <span
                          v-if="copiedStageId[stage.id]"
                          class="absolute left-1/2 -translate-x-1/2 top-full mt-1 px-2 py-1 text-xs rounded bg-slate-700 text-white whitespace-nowrap z-10"
                          >Copiado!</span
                        >
                      </div>
                      <button
                        type="button"
                        class="text-xs text-slate-400 hover:text-slate-500 p-0 m-0"
                        @click.stop="startEditing(stage)"
                      >
                        <fluent-icon icon="edit" size="14" />
                      </button>
                      <button
                        type="button"
                        class="text-slate-400 hover:text-slate-500 p-0 m-0"
                        @click.stop="removeStage(index)"
                      >
                        <fluent-icon icon="delete" size="14" />
                      </button>
                    </div>
                  </div>
                  <div
                    class="stage-preview-details p-0 max-h-0 opacity-0 overflow-hidden transition-all duration-200 ease-in-out group-hover:px-3 group-hover:pb-3 group-hover:opacity-100 group-hover:max-h-[500px] group-hover:pointer-events-auto pointer-events-none"
                  >
                    <div class="text-sm text-slate-600 mb-2">
                      {{ stage.description }}
                    </div>

                    <!-- Estatísticas da Etapa -->
                    <div v-if="stageStats[stage.id]" class="mb-2 px-1">
                      <div class="grid grid-cols-2 gap-2 text-xs">
                        <div class="flex justify-between items-center">
                          <span
                            class="bg-white dark:bg-slate-700 text-slate-600 dark:text-slate-300 px-1.5 py-0.5 rounded text-xs font-medium"
                            >itens</span>
                          <span
                            class="text-slate-700 dark:text-slate-200 font-medium"
                            >{{ stageStats[stage.id].count || 0 }}</span>
                        </div>
                        <div class="flex justify-between items-center">
                          <span
                            class="bg-white dark:bg-slate-700 text-slate-600 dark:text-slate-300 px-1.5 py-0.5 rounded text-xs font-medium"
                            >valor</span>
                          <span
                            class="text-slate-700 dark:text-slate-200 font-medium"
                            >{{
                              formatCurrency(
                                stageStats[stage.id].total_value || 0
                              )
                            }}</span>
                        </div>
                      </div>
                    </div>

                    <div
                      v-if="
                        stage.auto_create_conditions &&
                        stage.auto_create_conditions.length > 0
                      "
                      class="mt-1"
                    >
                      <div class="flex flex-wrap gap-1">
                        <span
                          v-for="(
                            condition, index
                          ) in stage.auto_create_conditions"
                          :key="index"
                          class="text-xs px-1 py-0.5 bg-slate-100 dark:bg-slate-700 rounded"
                        >
                          {{ getConditionTypeLabel(condition.type) }}:
                          {{ condition.value }}
                        </span>
                      </div>
                    </div>

                    <!-- Indicador de Checklist Templates -->
                    <div
                      v-if="
                        stage.checklist_templates &&
                        stage.checklist_templates.length > 0
                      "
                      class="mt-2"
                    >
                      <div
                        class="flex items-center gap-2 text-xs text-slate-600 dark:text-slate-400"
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
                          class="text-blue-500"
                        >
                          <path d="M16 5H3" />
                          <path d="M16 12H3" />
                          <path d="M11 19H3" />
                          <path d="m15 18 2 2 4-4" />
                        </svg>
                        <span class="font-medium">{{ stage.checklist_templates.length }} checklist{{
                            stage.checklist_templates.length !== 1 ? 's' : ''
                          }}
                          pré-configurado{{
                            stage.checklist_templates.length !== 1 ? 's' : ''
                          }}</span>
                      </div>
                    </div>
                  </div>
                </div>
              </template>
            </draggable>

            <!-- Empty State -->
            <div
              v-if="!stages.length"
              class="flex flex-col items-center justify-center py-8 text-slate-400"
            >
              <fluent-icon icon="list" size="32" class="mb-2" />
              <p class="text-sm">
                {{ t('KANBAN.FUNNELS.FORM.STAGES.EMPTY') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Agentes do Funil -->
        <div class="rounded-lg space-y-4 mt-6">
          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-2 text-sm font-medium">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="lucide lucide-users-icon lucide-users"
              >
                <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
                <path d="M16 3.128a4 4 0 0 1 0 7.744" />
                <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
                <circle cx="9" cy="7" r="4" />
              </svg>
              <span>{{ t('KANBAN.FUNNELS.FORM.SECTIONS.FUNNEL_AGENTS') }}</span>
            </div>
            <button
              type="button"
              class="flex items-center justify-center w-8 h-8 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800"
              @click="toggleAgents"
            >
              <fluent-icon
                :icon="agentsCollapsed ? 'chevron-down' : 'chevron-up'"
                size="16"
              />
            </button>
          </div>
          <!-- Select com busca -->
          <div
            v-show="!agentsCollapsed"
            ref="agentSelectorRef"
            class="relative mb-2"
          >
            <input
              v-model="agentSearch"
              type="text"
              class="w-full px-3 py-2 border rounded-lg"
              placeholder="Buscar agente..."
              @focus="openAgentDropdown"
              @input="openAgentDropdown"
            />
            <div
              v-if="agentDropdownOpen"
              class="absolute left-0 top-full w-full bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-lg max-h-60 overflow-y-auto scrollbar-hide z-[99999]"
            >
              <div
                v-for="agent in filteredAgents"
                :key="agent.id"
                class="px-3 py-2 hover:bg-woot-50 dark:hover:bg-slate-700 cursor-pointer flex items-center gap-2"
                @click="addAgent(agent)"
              >
                <Avatar
                  :name="agent.name"
                  :src="agent.avatar_url"
                  :size="24"
                  :status="agent.availability_status"
                />
                <div class="flex items-center gap-2 flex-1">
                  <span class="text-sm">{{ agent.name }}</span>
                  <span
                    class="px-2 py-0.5 text-xs bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300 rounded-full capitalize"
                    >{{ agent.role }}</span>
                </div>
              </div>
              <div
                v-if="filteredAgents.length === 0"
                class="px-3 py-2 text-slate-400 text-sm"
              >
                Nenhum agente encontrado
              </div>
            </div>
          </div>
          <!-- Listagem compacta dos agentes selecionados -->
          <div
            v-if="formData.agents.length"
            v-show="!agentsCollapsed"
            class="space-y-1"
          >
            <div
              class="flex items-center justify-between px-2 py-1 bg-slate-50 dark:bg-slate-800 rounded-lg mb-2"
            >
              <span class="text-sm text-slate-600 dark:text-slate-300">
                {{ formData.agents.length }} agente{{
                  formData.agents.length !== 1 ? 's' : ''
                }}
                selecionado{{ formData.agents.length !== 1 ? 's' : '' }}
              </span>
              <button
                type="button"
                class="text-xs text-ruby-500 hover:text-ruby-600 dark:text-ruby-400 dark:hover:text-ruby-300"
                @click="formData.agents = []"
              >
                Limpar seleção
              </button>
            </div>
            <div
              v-for="agent in formData.agents"
              :key="agent.id"
              class="flex items-center gap-2 px-2 py-1 border border-slate-100 dark:border-slate-800 rounded mb-1"
            >
              <Avatar
                :name="agent.name"
                :src="agent.avatar_url"
                :size="24"
                :status="agent.availability_status"
              />
              <div class="flex items-center gap-2 flex-1">
                <span class="text-sm">{{ agent.name }}</span>
                <span
                  class="px-2 py-0.5 text-xs bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300 rounded-full capitalize"
                  >{{ agent.role }}</span>
              </div>
              <button
                type="button"
                class="ml-auto text-xs text-ruby-500 hover:text-ruby-600"
                @click="removeAgent(agent)"
              >
                ✕
              </button>
            </div>
          </div>
        </div>

        <!-- Modelos de Mensagem -->
        <div class="mt-4 rounded-lg space-y-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2 text-sm font-medium">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="lucide lucide-messages-square-icon lucide-messages-square"
              >
                <path
                  d="M16 10a2 2 0 0 1-2 2H6.828a2 2 0 0 0-1.414.586l-2.202 2.202A.71.71 0 0 1 2 14.286V4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"
                />
                <path
                  d="M20 9a2 2 0 0 1 2 2v10.286a.71.71 0 0 1-1.212.502l-2.202-2.202A2 2 0 0 0 17.172 19H10a2 2 0 0 1-2-2v-1"
                />
              </svg>
              <span>{{
                t('KANBAN.FUNNELS.FORM.SECTIONS.MESSAGE_TEMPLATES')
              }}</span>
            </div>
            <div class="flex items-center gap-2">
              <span
                class="px-2 py-1 text-xs bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 rounded-full"
              >
                {{ getTotalMessageTemplates() }}
              </span>
              <button
                type="button"
                class="flex items-center justify-center w-8 h-8 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800"
                @click="toggleTemplates"
              >
                <fluent-icon
                  :icon="templatesCollapsed ? 'chevron-down' : 'chevron-up'"
                  size="16"
                />
              </button>
            </div>
          </div>

          <div v-show="!templatesCollapsed" class="space-y-2 scrollbar-hide">
            <div
              v-for="stage in stages"
              :key="stage.id"
              class="border border-slate-50 dark:border-slate-700 rounded p-2"
            >
              <div class="flex items-center gap-2 mb-1">
                <div
                  class="w-3 h-3 rounded-full"
                  :style="{ backgroundColor: stage.color }"
                />
                <span class="text-sm font-medium">{{ stage.name }}</span>
                <span class="text-xs text-slate-500">
                  ({{ (stage.message_templates || []).length }})
                </span>
              </div>

              <div
                v-if="(stage.message_templates || []).length > 0"
                class="space-y-1"
              >
                <div
                  v-for="template in (stage.message_templates || []).slice(
                    0,
                    2
                  )"
                  :key="template.id"
                  class="text-xs p-1 bg-slate-50 dark:bg-slate-800 rounded flex justify-between items-center"
                >
                  <span class="truncate flex-1">{{ template.title }}</span>
                  <span class="text-slate-400 ml-2">{{
                    template.created_at
                      ? new Date(template.created_at).toLocaleDateString()
                      : ''
                  }}</span>
                </div>
                <div
                  v-if="(stage.message_templates || []).length > 2"
                  class="text-xs text-slate-500 text-center"
                >
                  +{{ (stage.message_templates || []).length - 2 }} mais...
                </div>
              </div>

              <div v-else class="text-xs text-slate-400 italic">
                Nenhum template nesta etapa
              </div>
            </div>
          </div>
        </div>

        <!-- Status e Configurações -->
        <div class="mt-6 space-y-4">
          <!-- Histórico de Otimizações -->
          <div
            v-if="funnelMetadata.optimization_history?.length > 0"
            class="space-y-2"
          >
            <label
              class="text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              Histórico de Otimizações
            </label>
            <div class="space-y-1">
              <div
                v-for="(
                  optimization, index
                ) in funnelMetadata.optimization_history.slice(-3)"
                :key="index"
                class="text-xs text-slate-500 dark:text-slate-400 bg-slate-50 dark:bg-slate-800 px-2 py-1 rounded"
              >
                {{ new Date(optimization.date).toLocaleDateString() }} -
                {{ optimization.type }}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </form>
</template>

<style lang="scss" scoped>
.border-woot {
  border-color: var(--color-woot);
  border-width: 1px;
}

.ghost-card {
  opacity: 0.5;
  background: #c8ebfb;
}

.cursor-move {
  cursor: move;
}

.loading-spinner {
  @apply w-6 h-6 border-2 border-slate-200 border-t-woot-500 rounded-full animate-spin;
}

.agent-card {
  @apply transition-all duration-200;

  &:hover {
    @apply transform scale-[1.02];
  }
}

// Oculta a scrollbar mas permite scroll
.scrollbar-hide {
  scrollbar-width: none !important; /* Firefox */
  -ms-overflow-style: none !important; /* IE 10+ */
}
.scrollbar-hide::-webkit-scrollbar {
  display: none !important; /* Chrome/Safari/Webkit */
}

/* Força ocultar scrollbar em todos os elementos */
.funnel-form {
  scrollbar-width: none !important;
  -ms-overflow-style: none !important;
}
.funnel-form::-webkit-scrollbar {
  display: none !important;
}

.fade-enter-active,
.fade-leave-active {
  transition: all 0.2s;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
  max-height: 0;
}
.fade-enter-to,
.fade-leave-from {
  opacity: 1;
  max-height: 500px;
}
.stage-preview-card {
  position: relative;
}
.stage-preview-card {
  background: var(--tw-bg-opacity, 1) var(--tw-gradient, none);
}
.stage-preview-card:hover {
  background: var(--tw-gradient);
}
.stage-preview-details {
  /* Remove bg e gradiente daqui, fica só no card externo */
}

// Estilos para o colapso vertical do grupo Dados Básicos
.collapsible-content {
  transition: all 0.3s ease-in-out;
}
</style>
