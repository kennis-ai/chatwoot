<script setup>
import { ref, onMounted, computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import FunnelAPI from '../../../../api/funnel';
import MessageAPI from '../../../../api/inbox/message';
import axios from 'axios';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { emitter } from 'shared/helpers/mitt';
import Button from '../../../../components-next/button/Button.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  currentStage: {
    type: String,
    required: true,
  },
  contact: {
    type: Object,
    default: () => ({}),
  },
  conversation: {
    type: Object,
    default: () => ({}),
  },
  item: {
    type: Object,
    required: true,
  },
  items: {
    type: Array,
    default: () => [],
  },
  isBulk: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'send']);
const { t } = useI18n();

const loading = ref(false);
const sendingMessage = ref(false);
const funnels = ref([]);
const error = ref(null);
const messageError = ref(null);
const selectedTemplate = ref(null);
const showCustomMessage = ref(false);
const customMessage = ref('');

// Mapeamento de prioridades inglês -> português
const PRIORITY_MAP = {
  urgent: 'Urgente',
  high: 'Alta',
  medium: 'Média',
  low: 'Baixa',
  none: 'Nenhuma',
};

// Função para gerar um ID único no formato do Chatwoot
const generateMessageId = () => {
  return `${Math.random().toString(36).substring(2, 8)}${Date.now().toString(36)}`;
};

// Busca os funis e seus templates
const fetchFunnels = async () => {
  try {
    loading.value = true;
    const response = await FunnelAPI.get();
    funnels.value = response.data;
  } catch (err) {
    error.value = err.message;
    console.error('Erro ao carregar funis:', err);
  } finally {
    loading.value = false;
  }
};

// Retorna os templates da etapa atual
const currentStageTemplates = computed(() => {
  const templates = [];

  funnels.value.forEach(funnel => {
    if (funnel.stages[props.currentStage]?.message_templates) {
      templates.push(...funnel.stages[props.currentStage].message_templates);
    }
  });

  return templates;
});

// Retorna a cor da etapa atual
const currentStageColor = computed(() => {
  const funnel = funnels.value.find(f => f.stages[props.currentStage]);
  return funnel?.stages[props.currentStage]?.color || '#E5E7EB';
});

// Função para executar o webhook
const executeWebhook = async (webhook, data) => {
  try {
    await axios({
      method: webhook.method,
      url: webhook.url,
      data: {
        template_id: selectedTemplate.value.id,
        template_title: selectedTemplate.value.title,
        conversation_id: props.conversationId,
        contact: props.contact,
        message: data.message,
        channel: props.conversation?.meta?.channel,
        stage: props.currentStage,
        timestamp: new Date().toISOString(),
      },
    });
  } catch (error) {
    console.error('Erro ao executar webhook:', error);
    throw error;
  }
};

// Função para verificar se as condições do template são atendidas
const checkTemplateConditions = (template, item) => {
  console.log('Verificando condições do template:', {
    template_id: template.id,
    template_title: template.title,
    conditions: template.conditions,
    item_details: item.item_details,
  });

  // Se não tiver condições habilitadas, retorna true
  if (!template.conditions?.enabled) {
    console.log('Template não tem condições habilitadas, permitindo envio');
    return true;
  }

  // Se não tiver regras, retorna true
  if (!template.conditions.rules?.length) {
    console.log('Template não tem regras definidas, permitindo envio');
    return true;
  }

  // Verifica cada regra
  return template.conditions.rules.every(rule => {
    console.log('Verificando regra:', rule);
    const fieldValue = rule.field
      .split('.')
      .reduce((obj, key) => obj?.[key], item);

    // Se o campo for priority, faz o mapeamento
    const mappedFieldValue = rule.field.endsWith('priority')
      ? PRIORITY_MAP[fieldValue] || fieldValue
      : fieldValue;

    // Normaliza os valores para comparação
    const normalizedFieldValue = String(mappedFieldValue).toLowerCase().trim();
    const normalizedRuleValue = String(rule.value).toLowerCase().trim();

    console.log('Valor do campo:', fieldValue);
    console.log('Valor mapeado:', mappedFieldValue);
    console.log('Valor esperado:', rule.value);
    console.log('Valor normalizado do campo:', normalizedFieldValue);
    console.log('Valor normalizado esperado:', normalizedRuleValue);

    switch (rule.operator) {
      case 'equals':
        console.log(
          'Operador equals:',
          normalizedFieldValue === normalizedRuleValue
        );
        return normalizedFieldValue === normalizedRuleValue;
      case 'not_equals':
        console.log(
          'Operador not_equals:',
          normalizedFieldValue !== normalizedRuleValue
        );
        return normalizedFieldValue !== normalizedRuleValue;
      case 'contains':
        console.log(
          'Operador contains:',
          normalizedFieldValue.includes(normalizedRuleValue)
        );
        return normalizedFieldValue.includes(normalizedRuleValue);
      case 'not_contains':
        console.log(
          'Operador not_contains:',
          !normalizedFieldValue.includes(normalizedRuleValue)
        );
        return !normalizedFieldValue.includes(normalizedRuleValue);
      case 'greater_than':
        console.log(
          'Operador greater_than:',
          Number(fieldValue) > Number(rule.value)
        );
        return Number(fieldValue) > Number(rule.value);
      case 'less_than':
        console.log(
          'Operador less_than:',
          Number(fieldValue) < Number(rule.value)
        );
        return Number(fieldValue) < Number(rule.value);
      default:
        console.log('Operador desconhecido:', rule.operator);
        return false;
    }
  });
};

const handleSendMessage = async () => {
  try {
    sendingMessage.value = true;
    const messageContent = showCustomMessage.value
      ? customMessage.value
      : selectedTemplate.value.content;

    if (props.isBulk) {
      // Enviar para múltiplos itens
      await Promise.all(
        props.items.map(item =>
          MessageAPI.create({
            conversationId: item.item_details.conversation.display_id,
            message: messageContent,
            private: false,
            message_type: 'outgoing',
            inbox_id: item.item_details.conversation?.inbox_id || 1,
          })
        )
      );
    } else {
      // Envio único
      await MessageAPI.create({
        conversationId: props.conversationId,
        message: messageContent,
        private: false,
        message_type: 'outgoing',
        inbox_id: props.conversation?.inbox_id || 1,
      });
    }

    emitter.emit('newToastMessage', {
      message: props.isBulk
        ? 'Mensagens enviadas com sucesso'
        : 'Mensagem enviada com sucesso',
      action: { type: 'success' },
    });

    emit('send');
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: 'Erro ao enviar mensagem(ns)',
      action: { type: 'error' },
    });
    // Log detalhado do erro capturado
    console.error('Erro detalhado em handleSendMessage:', error);
  } finally {
    sendingMessage.value = false;
  }
};

const handleTemplateDelete = async (template, stageId) => {
  try {
    loading.value = true;
    await FunnelAPI.deleteTemplate(stageId, template.id);
    await fetchFunnels();

    emitter.emit('newToastMessage', {
      message: 'Modelo de mensagem excluído com sucesso',
      action: { type: 'success' },
    });
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: 'Erro ao excluir o modelo de mensagem',
      action: { type: 'error' },
    });
  } finally {
    loading.value = false;
  }
};

const initialize = () => {
  fetchFunnels();
};

onMounted(() => {
  initialize();
});

onBeforeUnmount(() => {
  // Limpa os estados ao desmontar
  selectedTemplate.value = null;
  funnels.value = [];
  error.value = null;
});

// Computed para formatar o nome do canal
const channelName = computed(() => {
  const channelType = props.conversation?.meta?.channel;
  const channelMap = {
    'Channel::WebWidget': {
      name: 'Website',
    },
    'Channel::Api': {
      name: 'API',
    },
    'Channel::Email': {
      name: 'Email',
    },
    'Channel::TwitterProfile': {
      name: 'Twitter',
    },
    'Channel::FacebookPage': {
      name: 'Facebook',
    },
    'Channel::TelegramBot': {
      name: 'Telegram',
    },
    'Channel::WhatsApp': {
      name: 'WhatsApp',
    },
  };

  return channelMap[channelType] || { name: 'Chat' };
});
</script>

<template>
  <div class="send-message-template">
    <div class="modal-content">
      <!-- Informações do Contato -->
      <div
        class="border border-dashed border-woot-500 dark:border-woot-400 rounded-lg p-4 mb-4 bg-woot-50/10 dark:bg-woot-900/10"
      >
        <!-- Cabeçalho com Informações Principais -->
        <div class="flex items-center gap-3 mb-3">
          <Avatar :src="contact?.thumbnail" :name="contact?.name" :size="40" />
          <div class="flex-1">
            <h4 class="text-sm font-medium text-woot-600 dark:text-woot-400">
              {{ contact?.name || t('KANBAN.ITEM_CONVERSATION.NO_CONTACT') }}
            </h4>
            <div class="flex items-center gap-2 text-xs text-slate-500">
              <span v-if="contact?.email">
                <span class="material-icons-outlined text-sm mr-1">mail</span>
                {{ t('KANBAN.ITEM_CONVERSATION.CONTACT.EMAIL') }}:
                {{ contact.email }}
              </span>
              <span v-if="contact?.phone_number">
                <span class="material-icons-outlined text-sm mr-1">phone</span>
                {{ t('KANBAN.ITEM_CONVERSATION.CONTACT.PHONE') }}:
                {{ contact.phone_number }}
              </span>
            </div>
          </div>
          <div
            v-if="conversation?.unread_count"
            class="flex items-center justify-center h-6 min-w-[1.5rem] px-2 bg-ruby-500 text-white text-xs font-medium rounded-full"
          >
            {{
              conversation.unread_count > 9 ? '9+' : conversation.unread_count
            }}
          </div>
        </div>

        <!-- Detalhes da Conversa -->
        <div
          class="grid grid-cols-2 gap-4 mb-3 pt-3 border-t border-woot-200/50 dark:border-woot-700/50"
        >
          <div>
            <p
              class="text-[10px] uppercase tracking-wider text-woot-500 dark:text-woot-400 mb-1"
            >
              Canal
            </p>
            <div class="flex items-center gap-2">
              <span class="text-xs text-slate-700 dark:text-slate-300">
                {{ channelName.name }}
              </span>
            </div>
          </div>
          <div>
            <p
              class="text-[10px] uppercase tracking-wider text-woot-500 dark:text-woot-400 mb-1"
            >
              Status
            </p>
            <div class="flex items-center gap-2">
              <span
                class="w-2 h-2 rounded-full"
                :class="{
                  'bg-green-500': conversation?.status === 'open',
                  'bg-yellow-500': conversation?.status === 'pending',
                  'bg-slate-500': conversation?.status === 'resolved',
                }"
              />
              <span
                class="text-xs capitalize text-slate-700 dark:text-slate-300"
              >
                {{ conversation?.status || 'desconhecido' }}
              </span>
            </div>
          </div>
        </div>

        <!-- Rodapé com ID e Timestamps -->
        <div
          class="flex items-center justify-between text-[10px] pt-3 border-t border-woot-200/50 dark:border-woot-700/50"
        >
          <div class="text-woot-500 dark:text-woot-400">
            Conversa #{{ conversation?.id }}
          </div>
          <div class="flex items-center gap-3 text-slate-500">
            <span v-if="conversation?.created_at">
              Criado em:
              {{ new Date(conversation.created_at).toLocaleDateString() }}
            </span>
            <span v-if="conversation?.last_activity_at">
              Última atividade:
              {{ new Date(conversation.last_activity_at).toLocaleDateString() }}
            </span>
          </div>
        </div>
      </div>

      <!-- Instruções -->
      <div v-if="!showCustomMessage" class="mb-4">
        <h4 class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-1">
          Selecione um template
        </h4>
        <p class="text-xs text-slate-500 dark:text-slate-400">
          Escolha um template para enviar uma mensagem pré-definida
        </p>
      </div>

      <!-- Loading State -->
      <div
        v-if="loading && !showCustomMessage"
        class="flex items-center justify-center py-8"
      >
        <span class="loading-spinner" />
      </div>

      <!-- Error State -->
      <div
        v-else-if="error && !showCustomMessage"
        class="flex flex-col items-center justify-center py-8"
      >
        <fluent-icon icon="error" size="24" class="text-ruby-500 mb-2" />
        <p class="text-slate-600 dark:text-slate-400">
          Erro ao carregar templates
        </p>
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          class="mt-2"
          @click="fetchFunnels"
        >
          Tentar novamente
        </Button>
      </div>

      <!-- Content -->
      <div v-else class="templates-container">
        <!-- Templates Grid -->
        <div
          v-if="currentStageTemplates.length && !showCustomMessage"
          class="templates-grid"
        >
          <div
            class="templates-list grid grid-cols-2 gap-4 p-2 rounded-lg"
            :style="{
              backgroundColor: `${currentStageColor}15`,
              border: `1px solid ${currentStageColor}`,
            }"
          >
            <div
              v-for="template in currentStageTemplates"
              :key="template.id"
              class="template-item"
              :class="{ selected: selectedTemplate?.id === template.id }"
              @click="selectedTemplate = template"
            >
              <div class="template-info">
                <div class="flex items-center gap-2 mb-2">
                  <h5 class="template-title flex-1">{{ template.title }}</h5>
                </div>
                <p
                  class="template-content line-clamp-2"
                  :title="template.content"
                >
                  {{ template.content }}
                </p>
                <div class="flex items-center gap-2 mt-2">
                  <span
                    v-if="template.webhook?.enabled"
                    class="text-[10px] px-1.5 py-0.5 rounded-full bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-400"
                  >
                    Webhook
                  </span>
                  <span
                    v-if="template.conditions?.enabled"
                    class="text-[10px] px-1.5 py-0.5 rounded-full bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-400"
                  >
                    Condições
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div v-else-if="!showCustomMessage" class="empty-templates">
          <div
            class="flex flex-col items-center justify-center py-8 text-center"
          >
            <fluent-icon
              icon="document"
              size="24"
              class="text-slate-400 dark:text-slate-600 mb-2"
            />
            <h4
              class="text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >
              {{ t('KANBAN.MESSAGE_TEMPLATES.NO_TEMPLATES') }}
            </h4>
            <p class="text-xs text-slate-500 dark:text-slate-400">
              {{ t('KANBAN.MESSAGE_TEMPLATES.NO_TEMPLATES_DESCRIPTION') }}
            </p>
          </div>
        </div>

        <!-- Mensagem Personalizada -->
        <div class="mt-4 flex justify-center">
          <button
            class="text-sm text-woot-500 hover:text-woot-600 dark:text-woot-400 dark:hover:text-woot-300 hover:underline"
            @click="showCustomMessage = !showCustomMessage"
          >
            {{
              showCustomMessage
                ? t('KANBAN.SEND_MESSAGE.SELECT_TEMPLATE')
                : t('KANBAN.SEND_MESSAGE.CUSTOM_MESSAGE')
            }}
          </button>
        </div>
        <div v-if="showCustomMessage" class="mt-2">
          <textarea
            v-model="customMessage"
            class="w-full p-3 text-sm border border-slate-200 dark:border-slate-700 rounded-lg bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-300 placeholder-slate-400 dark:placeholder-slate-600 focus:outline-none focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
            :placeholder="t('KANBAN.SEND_MESSAGE.CUSTOM_MESSAGE_PLACEHOLDER')"
            rows="4"
          />
        </div>
      </div>
    </div>

    <footer class="modal-footer">
      <div v-if="messageError" class="mb-2 text-sm text-ruby-500 text-center">
        {{ messageError }}
      </div>
      <div class="flex justify-end gap-2">
        <Button variant="ghost" color="slate" size="sm" @click="emit('close')">
          {{ t('CANCEL') }}
        </Button>
        <Button
          variant="solid"
          color="blue"
          size="sm"
          :disabled="(!selectedTemplate && !customMessage) || sendingMessage"
          :isLoading="sendingMessage"
          @click="handleSendMessage"
        >
          {{
            sendingMessage
              ? t('KANBAN.SEND_MESSAGE.STATUS.SENDING')
              : selectedTemplate
                ? t('KANBAN.SEND_MESSAGE.ACTIONS.SEND_SELECTED', {
                    title: selectedTemplate.title,
                  })
                : customMessage
                  ? t('KANBAN.SEND_MESSAGE.ACTIONS.SEND_CUSTOM')
                  : t('KANBAN.SEND_MESSAGE.ACTIONS.SEND')
          }}
        </Button>
      </div>
    </footer>
  </div>
</template>

<style lang="scss" scoped>
.send-message-template {
  @apply flex flex-col h-full;
}

.modal-header {
  @apply p-4 border-b border-slate-200 dark:border-slate-700;
}

.modal-content {
  @apply p-4 flex-1 overflow-y-auto;
  max-height: 60vh;
}

.modal-footer {
  @apply p-4 border-t border-slate-200 dark:border-slate-700;
}

.loading-spinner {
  @apply w-8 h-8 border-2 border-slate-200 border-t-woot-500 rounded-full animate-spin;
}

.templates-grid {
  @apply space-y-4;
}

.stage-templates {
  @apply bg-white dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700 overflow-hidden;
}

.stage-title {
  @apply flex items-center gap-2 p-2 text-sm font-medium bg-slate-50 dark:bg-slate-700;
}

.stage-color {
  @apply w-3 h-3 rounded-full;
}

.templates-list {
  @apply p-2 overflow-y-auto max-h-[60vh];

  &::-webkit-scrollbar {
    @apply w-2;
  }

  &::-webkit-scrollbar-track {
    @apply bg-transparent;
  }

  &::-webkit-scrollbar-thumb {
    @apply rounded-full bg-slate-300 dark:bg-slate-600;
  }
}

.template-item {
  @apply p-4 rounded-lg border border-slate-200 dark:border-slate-700 cursor-pointer bg-white dark:bg-slate-800;

  &.selected {
    @apply border-2 border-woot-500 dark:border-woot-400 bg-woot-50 dark:bg-woot-900/10;

    .template-title {
      @apply text-woot-600 dark:text-woot-400;
    }

    .fluent-icon {
      @apply text-woot-500 dark:text-woot-400;
    }
  }
}

.template-title {
  @apply text-sm font-medium text-slate-700 dark:text-slate-200 truncate;
}

.template-content {
  @apply text-xs text-slate-500 dark:text-slate-400 overflow-hidden;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
}

.empty-templates {
  @apply text-sm text-center text-slate-500 dark:text-slate-400 py-4;
}
</style>
