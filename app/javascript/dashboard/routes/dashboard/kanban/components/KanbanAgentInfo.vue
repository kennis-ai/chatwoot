<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import KanbanAPI from '../../../../api/kanban';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  agentInfo: {
    type: Object,
    default: null,
  },
  loadingAgent: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['agentAssigned', 'agentRemoved']);

const { t } = useI18n();

const store = useStore();

// Computed para obter todos os agentes atribuídos
const assignedAgents = computed(() => {
  return props.item?.assigned_agents || [];
});

// Computed para obter a lista de agentes disponíveis
const agentList = computed(() => store.getters['agents/getAgents']);

// Modal de atribuição rápida de agente
const showAgentAssignModal = ref(false);
const agentAssignLoading = ref(false);
const selectedAgentId = ref(null);
const agentSearch = ref('');

// Computed para filtrar agentes baseado na busca
const filteredAgentList = computed(() => {
  if (!agentSearch.value) return agentList.value;
  return agentList.value.filter(agent =>
    (agent.name || '').toLowerCase().includes(agentSearch.value.toLowerCase())
  );
});

// Computed para obter o agente da conversa (se existir)
const conversationAgent = computed(() => {
  const conversation = props.item?.conversation;
  return conversation?.assignee || null;
});

// Função para formatar data de forma compacta
const formatDate = dateString => {
  if (!dateString) return '';
  try {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now - date;
    const diffHours = diffMs / (1000 * 60 * 60);
    const diffDays = diffMs / (1000 * 60 * 60 * 24);

    // Se for hoje, mostra apenas hora
    if (diffHours < 24 && date.toDateString() === now.toDateString()) {
      return date.toLocaleTimeString('pt-BR', {
        hour: '2-digit',
        minute: '2-digit',
      });
    }

    // Se for ontem, mostra "ontem"
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    if (date.toDateString() === yesterday.toDateString()) {
      return 'ontem';
    }

    // Se for nos últimos 7 dias, mostra dia da semana
    if (diffDays < 7) {
      const weekdays = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
      return weekdays[date.getDay()];
    }

    // Caso contrário, mostra dia/mês
    return date.toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
    });
  } catch (error) {
    return '';
  }
};

// Função para obter status de disponibilidade do agente da conversa
const getAgentAvailabilityStatus = agent => {
  if (!agent) return null;

  // Primeiro tenta obter do agente da conversa
  if (agent.availability_status) {
    return agent.availability_status;
  }

  // Fallback para 'online' se não especificado
  return 'online';
};

// Função para obter nome do status de disponibilidade
const getAvailabilityLabel = status => {
  switch (status) {
    case 'online':
      return 'Online';
    case 'offline':
      return 'Offline';
    case 'busy':
      return 'Ocupado';
    default:
      return 'Desconhecido';
  }
};

// Função para abrir modal
const openAgentAssignModal = () => {
  selectedAgentId.value = null;
  showAgentAssignModal.value = true;
};

// Função para atribuir agente
const assignAgent = async () => {
  if (!selectedAgentId.value || agentAssignLoading.value) return;
  agentAssignLoading.value = true;
  try {
    const { data } = await KanbanAPI.assignAgent(
      props.item.id,
      selectedAgentId.value
    );
    if (data) {
      emit('agentAssigned', data);
    }
    showAgentAssignModal.value = false;
    selectedAgentId.value = null;
  } catch (error) {
    console.error('Erro ao atribuir agente:', error);
  } finally {
    agentAssignLoading.value = false;
  }
};

// Função para remover agente
const removeAgent = async agentId => {
  try {
    const { data } = await KanbanAPI.removeAgent(props.item.id, agentId);
    if (data) {
      emit('agentRemoved', data);
    }
  } catch (error) {
    console.error('Erro ao remover agente:', error);
  }
};

// Função para obter o nome do agente que atribuiu baseado no ID
const getAssignedByName = assignedById => {
  if (!assignedById) return '';

  // Primeiro tenta encontrar na lista de agentes do funnel
  const funnelAgents = props.item?.funnel?.settings?.agents || [];
  const funnelAgent = funnelAgents.find(agent => agent.id === assignedById);

  if (funnelAgent) {
    return funnelAgent.name;
  }

  // Fallback para o agente principal se disponível
  if (props.agentInfo && props.agentInfo.id === assignedById) {
    return props.agentInfo.name;
  }

  // Último fallback: retorna o ID como string
  return assignedById.toString();
};
</script>

<template>
  <!-- Container principal com estilo consistente -->
  <div
    class="agent-info-container bg-white dark:bg-slate-800 rounded-xl p-4 border border-slate-100 dark:border-slate-700 shadow-sm"
  >
    <!-- Cabeçalho da seção com indicador de pulso -->
    <div class="agent-info-header flex items-center justify-between mb-4">
      <div class="flex items-center gap-2">
        <div class="w-2 h-2 bg-woot-500 rounded-full animate-pulse" />
        <h4 class="text-base font-semibold text-slate-900 dark:text-slate-100">
          {{ t('KANBAN.ITEM_DETAILS.AGENT_RESPONSIBLE') }}
        </h4>
      </div>

      <!-- Ícone para adicionar agente -->
      <button
        class="flex items-center justify-center p-1.5 text-slate-500 dark:text-slate-400 hover:text-woot-500 dark:hover:text-woot-400 hover:bg-woot-50 dark:hover:bg-woot-900/20 transition-all rounded-lg"
        title="Adicionar agente"
        @click="openAgentAssignModal"
      >
        <fluent-icon icon="person-add" size="14" class="text-current" />
      </button>
    </div>

    <!-- Conteúdo dos agentes -->
    <div class="agent-content space-y-3">
      <div v-if="loadingAgent" class="flex justify-center py-4">
        <span class="text-sm text-slate-500 dark:text-slate-400">
          {{ t('KANBAN.ITEM_DETAILS.LOADING_AGENT') }}
        </span>
      </div>
      <div
        v-else-if="assignedAgents && assignedAgents.length > 0"
        class="space-y-2"
      >
        <div
          v-for="agent in assignedAgents"
          :key="agent.id"
          class="flex items-center gap-3 p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-700 transition-colors"
        >
          <Avatar
            :name="agent.name"
            :src="agent.avatar_url || agent.thumbnail"
            :size="28"
          />
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 flex-wrap">
              <span
                class="text-sm font-medium text-slate-900 dark:text-slate-100 truncate"
              >
                {{ agent.name }}
              </span>
              <!-- Status de disponibilidade do agente da conversa -->
              <div
                v-if="conversationAgent && conversationAgent.id === agent.id"
                class="flex items-center gap-1 px-1.5 py-0.5 rounded-full text-xs font-medium"
                :class="{
                  'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300':
                    getAgentAvailabilityStatus(conversationAgent) === 'online',
                  'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-400':
                    getAgentAvailabilityStatus(conversationAgent) === 'offline',
                  'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300':
                    getAgentAvailabilityStatus(conversationAgent) === 'busy',
                }"
              >
                <div
                  class="w-1.5 h-1.5 rounded-full"
                  :class="{
                    'bg-green-500 animate-pulse':
                      getAgentAvailabilityStatus(conversationAgent) ===
                      'online',
                    'bg-slate-400':
                      getAgentAvailabilityStatus(conversationAgent) ===
                      'offline',
                    'bg-red-500':
                      getAgentAvailabilityStatus(conversationAgent) === 'busy',
                  }"
                />
                <span class="text-[10px]">
                  {{
                    getAgentAvailabilityStatus(conversationAgent) === 'online'
                      ? 'Online'
                      : getAgentAvailabilityStatus(conversationAgent) === 'busy'
                        ? 'Ocupado'
                        : 'Offline'
                  }}
                </span>
              </div>
              <span
                v-if="agent.id === agentInfo?.id"
                class="text-[10px] bg-woot-100 dark:bg-woot-900/50 text-woot-600 dark:text-woot-400 px-1.5 py-0.5 rounded-full"
              >
                Principal
              </span>
            </div>
            <!-- Data de atribuição apenas se houver -->
            <div
              v-if="agent.assigned_at"
              class="text-xs text-slate-500 dark:text-slate-400 mt-0.5"
            >
              Atribuído em {{ formatDate(agent.assigned_at) }}
            </div>
          </div>
          <!-- Botão de remover agente -->
          <button
            class="p-1 text-slate-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-all rounded-full"
            title="Remover agente"
            @click="removeAgent(agent.id)"
          >
            <fluent-icon icon="delete" size="14" />
          </button>
        </div>
      </div>
      <div
        v-else-if="agentInfo"
        class="flex items-center gap-3 p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg"
      >
        <Avatar :name="agentInfo.name" :src="agentInfo.avatar_url" :size="28" />
        <div class="flex-1">
          <span
            class="text-sm font-medium text-slate-900 dark:text-slate-100"
            >{{ agentInfo.name }}</span>
        </div>
      </div>
      <div v-else class="text-center py-6 text-slate-500 dark:text-slate-400">
        <fluent-icon icon="person" size="24" class="mx-auto mb-2 opacity-50" />
        <p class="text-sm">{{ t('KANBAN.ITEM_DETAILS.NO_AGENT') }}</p>
      </div>
    </div>

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
        <div v-if="assignedAgents.length > 0" class="mb-4">
          <h4
            class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-2"
          >
            Agentes Atribuídos ({{ assignedAgents.length }})
          </h4>
          <div class="space-y-2">
            <div
              v-for="agent in assignedAgents"
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
                assignedAgents.some(a => a.id === agent.id)
                  ? 'opacity-50 cursor-not-allowed'
                  : '',
              ]"
              :disabled="assignedAgents.some(a => a.id === agent.id)"
              @click="selectedAgentId = agent.id"
            >
              <Avatar
                :name="agent.name || 'Agente'"
                :src="agent.avatar_url || agent.thumbnail || ''"
                :size="20"
                class="mr-2"
              />
              <span class="truncate">{{ agent.name || 'Agente' }}</span>
              <span
                v-if="assignedAgents.some(a => a.id === agent.id)"
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
              assignedAgents.some(a => a.id === selectedAgentId)
            "
            @click="assignAgent"
          >
            Adicionar Agente
          </Button>
        </div>
      </div>
    </Modal>
  </div>
</template>

<style scoped>
/* Animações do componente de agentes */
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

/* Container principal */
.agent-info-container {
  animation: fade-in-up 0.6s ease-out;
}

.agent-info-header {
  animation: fade-in-up 0.4s ease-out;
}

/* Estado vazio melhorado */
.agent-content {
  animation: fade-in-up 0.8s ease-out;
}

/* Responsividade */
@media (max-width: 768px) {
  .agent-info-container {
    padding: 1rem;
  }

  .agent-info-header h4 {
    font-size: 0.875rem;
  }
}
</style>
