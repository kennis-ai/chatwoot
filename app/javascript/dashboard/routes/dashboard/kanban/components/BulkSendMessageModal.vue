<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import MessageAPI from '../../../../api/inbox/message';
import FunnelAPI from '../../../../api/funnel';
import KanbanAPI from '../../../../api/kanban';
import { emitter } from 'shared/helpers/mitt';
import Button from '../../../../components-next/button/Button.vue';

const props = defineProps({
  items: {
    type: Array,
    required: true,
  },
});
const emit = defineEmits(['close', 'send']);
const store = useStore();
const accountId = computed(() => store.getters.getCurrentAccount?.id);
const selectedFunnel = computed(
  () => store.getters['funnel/getSelectedFunnel']
);

const { t } = useI18n();

const loading = ref(false);
const sendingMessage = ref(false);
const templates = ref([]);
const selectedTemplate = ref(null);
const selectedConditions = ref({
  status: '',
  priority: '',
  hasAttachments: false,
  stage: '',
  assignee: '',
  lastActivity: '',
  tags: [],
  customFields: [],
});
const kanbanItems = ref([]);
const selectedConversations = ref(new Set());
const isProcessing = ref(false);
const processedItems = ref([]);
const successCount = ref(0);
const errorCount = ref(0);
const progress = ref(0);
const showFilters = ref(false);

// Buscar templates disponíveis
const fetchTemplates = async () => {
  try {
    loading.value = true;
    const response = await FunnelAPI.get();
    const allTemplates = [];

    response.data.forEach(funnel => {
      Object.values(funnel.stages).forEach(stage => {
        if (stage.message_templates) {
          allTemplates.push(...stage.message_templates);
        }
      });
    });

    templates.value = allTemplates;
  } catch (error) {
    console.error('Erro ao carregar templates:', error);
  } finally {
    loading.value = false;
  }
};

// Buscar itens do Kanban
const fetchKanbanItems = async () => {
  try {
    if (!selectedFunnel.value?.id) return;

    // Se props.items está vazio, buscar todos os itens do funil
    if (props.items.length === 0) {
      const response = await KanbanAPI.getItems(selectedFunnel.value.id);
      console.log('[DEBUG] Response completa:', response);
      console.log('[DEBUG] Response data:', response.data);

      // A resposta tem estrutura {items: Array, pagination: {...}}
      const itemsData = response.data?.items || [];
      console.log('[DEBUG] Items data (array):', itemsData.length);

      kanbanItems.value = itemsData;
      console.log(
        '[DEBUG] Usando todos os itens do funil:',
        kanbanItems.value.length
      );
    } else {
      // Usar diretamente os itens passados como props
      kanbanItems.value = props.items;
      console.log('[DEBUG] Usando itens dos props:', kanbanItems.value.length);
    }

    console.log(
      '[DEBUG] Items com conversa:',
      kanbanItems.value.filter(item => item.item_details?.conversation_id)
        .length
    );
    console.log(
      '[DEBUG] IDs das conversas:',
      kanbanItems.value.map(item => ({
        itemId: item.id,
        conversationId: item.item_details?.conversation_id,
        hasConversation: !!item.item_details?.conversation,
      }))
    );
  } catch (error) {
    console.error('Erro ao carregar itens:', error);
  }
};

// Computed para itens filtrados com todas as condições
const filteredItems = computed(() => {
  return kanbanItems.value.filter(item => {
    // Verifica se tem conversation_id
    if (!item.item_details?.conversation_id) return false;

    // Filtro por status
    if (
      selectedConditions.value.status &&
      item.item_details.status !== selectedConditions.value.status
    ) {
      return false;
    }

    // Filtro por prioridade
    if (
      selectedConditions.value.priority &&
      item.item_details.priority !== selectedConditions.value.priority
    ) {
      return false;
    }

    // Filtro por anexos
    if (selectedConditions.value.hasAttachments && !item.attachments?.length) {
      return false;
    }

    // Filtro por etapa
    if (
      selectedConditions.value.stage &&
      item.funnel_stage !== selectedConditions.value.stage
    ) {
      return false;
    }

    // Filtro por responsável
    if (
      selectedConditions.value.assignee &&
      item.item_details.agent_id !== selectedConditions.value.assignee
    ) {
      return false;
    }

    // Filtro por última atividade
    if (selectedConditions.value.lastActivity) {
      const lastActivity = new Date(
        item.item_details.conversation?.last_activity_at
      );
      const now = new Date();
      const diffDays = Math.floor((now - lastActivity) / (1000 * 60 * 60 * 24));

      switch (selectedConditions.value.lastActivity) {
        case 'today':
          if (diffDays > 0) return false;
          break;
        case 'week':
          if (diffDays > 7) return false;
          break;
        case 'month':
          if (diffDays > 30) return false;
          break;
      }
    }

    return true;
  });
});

const handleToggleConversation = item => {
  const id = item.item_details.conversation_id;
  if (selectedConversations.value.has(id)) {
    selectedConversations.value.delete(id);
  } else {
    selectedConversations.value.add(id);
  }
};

const handleSelectAll = () => {
  if (selectedConversations.value.size === filteredItems.value.length) {
    selectedConversations.value.clear();
  } else {
    selectedConversations.value = new Set(
      filteredItems.value.map(item => item.item_details.conversation_id)
    );
  }
};

const handleSend = async () => {
  if (!selectedTemplate.value || selectedConversations.value.size === 0) return;

  try {
    isProcessing.value = true;
    sendingMessage.value = true;
    processedItems.value = [];
    successCount.value = 0;
    errorCount.value = 0;
    progress.value = 0;

    const itemsToProcess = filteredItems.value.filter(item =>
      selectedConversations.value.has(item.item_details.conversation_id)
    );

    for (const item of itemsToProcess) {
      try {
        const conversationId = item.item_details.conversation_id;
        const inboxId = item.item_details.conversation?.inbox_id || 1;

        await MessageAPI.create({
          conversationId,
          message: selectedTemplate.value.content,
          private: false,
          message_type: 'outgoing',
          inbox_id: inboxId,
        });

        processedItems.value.push({
          id: item.id,
          title: item.item_details.title,
          conversationId,
          status: 'success',
        });
        successCount.value++;
      } catch (error) {
        processedItems.value.push({
          id: item.id,
          title: item.item_details.title,
          conversationId: item.item_details.conversation_id,
          status: 'error',
          error: error.message,
        });
        errorCount.value++;
      }

      progress.value =
        (processedItems.value.length / itemsToProcess.length) * 100;
    }

    emitter.emit('newToastMessage', {
      message: `Processo concluído: ${successCount.value} mensagens enviadas, ${errorCount.value} falhas`,
      action: { type: successCount.value > 0 ? 'success' : 'error' },
    });
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: 'Erro ao processar envios',
      action: { type: 'error' },
    });
  } finally {
    sendingMessage.value = false;
  }
};

const handleClose = () => {
  if (isProcessing.value) {
    isProcessing.value = false;
    processedItems.value = [];
    successCount.value = 0;
    errorCount.value = 0;
    progress.value = 0;
  }
  emit('close');
};

onMounted(() => {
  fetchTemplates();
  fetchKanbanItems();
});
</script>

<template>
  <div class="space-y-6">
    <!-- Tela de Progresso -->
    <div v-if="isProcessing" class="space-y-6">
      <div class="text-center space-y-2">
        <h3 class="text-lg font-medium">
          {{ t('KANBAN.BULK_ACTIONS.SEND_MESSAGE.PROCESSING_TITLE') }}
        </h3>
        <p class="text-sm text-slate-500">
          {{
            t('KANBAN.BULK_ACTIONS.SEND_MESSAGE.PROCESSING_DESCRIPTION', {
              count: processedItems.length,
              total: selectedConversations.size,
            })
          }}
        </p>
      </div>

      <!-- Barra de Progresso -->
      <div class="relative pt-1">
        <div class="flex mb-2 items-center justify-between">
          <div>
            <span
              class="text-xs font-semibold inline-block py-1 px-2 rounded-full"
              :class="{
                'text-emerald-600 bg-emerald-200': progress === 100,
                'text-woot-500 bg-woot-100': progress < 100,
              }"
            >
              {{ Math.round(progress) }}%
            </span>
          </div>
          <div class="text-right">
            <span class="text-xs font-semibold inline-block">
              {{ successCount }}
              {{ t('KANBAN.BULK_ACTIONS.SEND_MESSAGE.SUCCESS') }} •
              {{ errorCount }} {{ t('KANBAN.BULK_ACTIONS.SEND_MESSAGE.ERROR') }}
            </span>
          </div>
        </div>
        <div class="overflow-hidden h-2 mb-4 text-xs flex rounded bg-slate-200">
          <div
            :style="{ width: `${progress}%` }"
            class="transition-all duration-500 shadow-none flex flex-col text-center whitespace-nowrap text-white justify-center"
            :class="{
              'bg-emerald-500': progress === 100,
              'bg-woot-500': progress < 100,
            }"
          />
        </div>
      </div>

      <!-- Lista de Resultados -->
      <div class="border rounded-lg divide-y max-h-[400px] overflow-y-auto">
        <div
          v-for="item in processedItems"
          :key="item.id"
          class="p-3 flex items-center justify-between hover:bg-slate-50"
        >
          <div class="flex items-center gap-3">
            <span class="flex-shrink-0">
              <fluent-icon
                :icon="
                  item.status === 'success'
                    ? 'checkmark-circle'
                    : 'error-circle'
                "
                size="20"
                :class="
                  item.status === 'success'
                    ? 'text-emerald-500'
                    : 'text-ruby-500'
                "
              />
            </span>
            <div class="flex-1">
              <p class="text-sm font-medium">{{ item.title }}</p>
              <p class="text-xs text-slate-500">
                {{
                  t('KANBAN.BULK_ACTIONS.SEND_MESSAGE.CONVERSATION_ID', {
                    id: item.conversationId,
                  })
                }}
              </p>
              <p v-if="item.error" class="text-xs text-ruby-500 mt-1">
                {{ item.error }}
              </p>
            </div>
          </div>
          <span
            class="text-xs px-2 py-1 rounded-full"
            :class="
              item.status === 'success'
                ? 'bg-emerald-100 text-emerald-700'
                : 'bg-ruby-100 text-ruby-700'
            "
          >
            {{ item.status === 'success' ? 'Enviado' : 'Falha' }}
          </span>
        </div>
      </div>

      <!-- Ações -->
      <div class="flex justify-end">
        <Button variant="ghost" color="slate" size="sm" @click="handleClose">
          {{ t('KANBAN.BULK_ACTIONS.CANCEL') }}
        </Button>
      </div>
    </div>

    <!-- Conteúdo Original -->
    <div v-else class="space-y-6">
      <!-- Lista de conversas e Switch de Filtros -->
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <h4 class="text-sm font-medium">
            {{
              t('KANBAN.BULK_ACTIONS.SELECTED_CONVERSATIONS', {
                count: selectedConversations.size,
                total: filteredItems.length,
              })
            }}
          </h4>
          <div class="flex items-center gap-4">
            <label class="flex items-center gap-2 text-sm">
              <input v-model="showFilters" type="checkbox" class="toggle" />
              <span>{{ t('KANBAN.BULK_ACTIONS.FILTER_ITEMS') }}</span>
            </label>
            <Button
              variant="ghost"
              color="slate"
              size="sm"
              @click="handleSelectAll"
            >
              {{
                selectedConversations.size === filteredItems.length
                  ? t('KANBAN.BULK_ACTIONS.DESELECT_ALL')
                  : t('KANBAN.BULK_ACTIONS.SELECT_ALL')
              }}
            </Button>
          </div>
        </div>

        <!-- Bloco de Filtros -->
        <div v-if="showFilters" class="space-y-4">
          <!-- Resumo dos Filtros -->
          <div class="bg-woot-50 p-4 rounded-lg space-y-2">
            <div class="flex items-center justify-between">
              <h4 class="text-sm font-medium">
                {{ t('KANBAN.BULK_ACTIONS.FILTERS_ACTIVE') }}
              </h4>
              <Button
                variant="ghost"
                color="slate"
                size="sm"
                @click="
                  selectedConditions = {
                    status: '',
                    priority: '',
                    hasAttachments: false,
                    stage: '',
                    assignee: '',
                    lastActivity: '',
                    tags: [],
                    customFields: [],
                  }
                "
              >
                {{ t('KANBAN.BULK_ACTIONS.CLEAR_FILTERS') }}
              </Button>
            </div>
            <div class="flex flex-wrap gap-2">
              <template v-for="(value, key) in selectedConditions" :key="key">
                <span
                  v-if="value && typeof value !== 'boolean'"
                  class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-full bg-woot-100"
                >
                  {{ key }}: {{ value }}
                  <button
                    class="text-slate-500 hover:text-slate-700"
                    @click="selectedConditions[key] = ''"
                  >
                    ×
                  </button>
                </span>
                <span
                  v-else-if="value === true"
                  class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-full bg-woot-100"
                >
                  {{ key }}
                  <button
                    class="text-slate-500 hover:text-slate-700"
                    @click="selectedConditions[key] = false"
                  >
                    ×
                  </button>
                </span>
              </template>
            </div>
          </div>

          <!-- Condições de Filtro -->
          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <h4 class="text-sm font-medium">
                {{ t('KANBAN.BULK_ACTIONS.FILTER_CONVERSATIONS') }}
              </h4>
              <span class="text-xs text-slate-500">
                {{
                  t('KANBAN.BULK_ACTIONS.FILTER_CONVERSATIONS_COUNT', {
                    count: filteredItems.length,
                  })
                }}
              </span>
            </div>

            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm mb-2">
                  {{ t('KANBAN.BULK_ACTIONS.ITEM_STATUS.TITLE') }}
                </label>
                <select
                  v-model="selectedConditions.status"
                  class="w-full rounded-lg"
                >
                  <option value="">
                    {{ t('KANBAN.BULK_ACTIONS.ITEM_STATUS.ALL') }}
                  </option>
                  <option value="open">
                    {{ t('KANBAN.BULK_ACTIONS.ITEM_STATUS.OPEN') }}
                  </option>
                  <option value="won">
                    {{ t('KANBAN.BULK_ACTIONS.ITEM_STATUS.WON') }}
                  </option>
                  <option value="lost">
                    {{ t('KANBAN.BULK_ACTIONS.ITEM_STATUS.LOST') }}
                  </option>
                </select>
              </div>

              <div>
                <label class="block text-sm mb-2">
                  {{ t('KANBAN.BULK_ACTIONS.PRIORITY.TITLE') }}
                </label>
                <select
                  v-model="selectedConditions.priority"
                  class="w-full rounded-lg"
                >
                  <option value="">
                    {{ t('KANBAN.BULK_ACTIONS.PRIORITY.ALL') }}
                  </option>
                  <option value="urgent">
                    {{ t('KANBAN.BULK_ACTIONS.PRIORITY.URGENT') }}
                  </option>
                  <option value="high">
                    {{ t('KANBAN.BULK_ACTIONS.PRIORITY.HIGH') }}
                  </option>
                  <option value="medium">
                    {{ t('KANBAN.BULK_ACTIONS.PRIORITY.MEDIUM') }}
                  </option>
                  <option value="low">
                    {{ t('KANBAN.BULK_ACTIONS.PRIORITY.LOW') }}
                  </option>
                </select>
              </div>

              <div>
                <label class="block text-sm mb-2">
                  {{ t('KANBAN.BULK_ACTIONS.STAGE.TITLE') }}
                </label>
                <select
                  v-model="selectedConditions.stage"
                  class="w-full rounded-lg"
                >
                  <option value="">
                    {{ t('KANBAN.BULK_ACTIONS.STAGE.ALL') }}
                  </option>
                  <option
                    v-for="stage in Object.keys(
                      selectedFunnel.value?.stages || {}
                    )"
                    :key="stage"
                    :value="stage"
                  >
                    {{ selectedFunnel.value?.stages[stage]?.name }}
                  </option>
                </select>
              </div>

              <div>
                <label class="block text-sm mb-2">
                  {{ t('KANBAN.BULK_ACTIONS.LAST_ACTIVITY.TITLE') }}
                </label>
                <select
                  v-model="selectedConditions.lastActivity"
                  class="w-full rounded-lg"
                >
                  <option value="">
                    {{ t('KANBAN.BULK_ACTIONS.LAST_ACTIVITY.ANY') }}
                  </option>
                  <option value="today">
                    {{ t('KANBAN.BULK_ACTIONS.LAST_ACTIVITY.TODAY') }}
                  </option>
                  <option value="week">
                    {{ t('KANBAN.BULK_ACTIONS.LAST_ACTIVITY.WEEK') }}
                  </option>
                  <option value="month">
                    {{ t('KANBAN.BULK_ACTIONS.LAST_ACTIVITY.MONTH') }}
                  </option>
                </select>
              </div>
            </div>

            <div class="flex items-center gap-4">
              <label class="flex items-center gap-2">
                <input
                  v-model="selectedConditions.hasAttachments"
                  type="checkbox"
                  class="rounded"
                />
                <span class="text-sm">
                  {{ t('KANBAN.BULK_ACTIONS.HAS_ATTACHMENTS') }}
                </span>
              </label>
            </div>
          </div>
        </div>

        <!-- Lista de Conversas -->
        <div
          v-if="filteredItems.length > 0"
          class="max-h-60 overflow-y-auto border rounded-lg divide-y"
        >
          <div
            v-for="item in filteredItems"
            :key="item.id"
            class="p-2 text-sm hover:bg-slate-50 flex items-center gap-2 cursor-pointer"
            @click="handleToggleConversation(item)"
          >
            <input
              type="checkbox"
              :checked="
                selectedConversations.has(item.item_details.conversation_id)
              "
              class="rounded"
              @click.stop
            />
            <span>
              {{ item.item_details.title }} -
              {{
                t('KANBAN.BULK_ACTIONS.CONVERSATION_ID', {
                  id: item.item_details.conversation_id,
                })
              }}
            </span>
          </div>
        </div>
        <div v-else class="text-center text-sm text-slate-500 py-4">
          {{ t('KANBAN.BULK_ACTIONS.NO_CONVERSATIONS_AVAILABLE') }}
        </div>
      </div>

      <!-- Seleção de Template -->
      <div class="space-y-4">
        <h4 class="text-sm font-medium">
          {{ t('KANBAN.BULK_ACTIONS.SELECT_MESSAGE_TEMPLATE') }}
        </h4>

        <div v-if="loading" class="flex justify-center">
          <span class="loading-spinner" />
        </div>

        <div v-else class="space-y-4">
          <select
            v-model="selectedTemplate"
            class="w-full rounded-lg"
            :class="{ 'border-ruby-500': !selectedTemplate }"
          >
            <option value="">
              {{ t('KANBAN.BULK_ACTIONS.MESSAGE_TEMPLATE_SELECT') }}
            </option>
            <option
              v-for="template in templates"
              :key="template.id"
              :value="template"
            >
              {{ template.title }}
            </option>
          </select>

          <div v-if="selectedTemplate" class="p-4 bg-slate-50 rounded-lg">
            <p class="text-sm">{{ selectedTemplate.content }}</p>
          </div>
        </div>
      </div>

      <!-- Resumo -->
      <div class="p-4 bg-woot-50 rounded-lg">
        <p class="text-sm">
          {{
            t('KANBAN.BULK_ACTIONS.MESSAGE_SUMMARY', {
              count: selectedConversations.size,
              total: items.length,
            })
          }}
        </p>
      </div>

      <!-- Ações -->
      <div class="flex justify-end gap-2">
        <Button variant="ghost" color="slate" size="sm" @click="handleClose">
          Cancelar
        </Button>
        <Button
          variant="solid"
          color="blue"
          size="sm"
          :is-loading="sendingMessage"
          :disabled="!selectedTemplate || selectedConversations.size === 0"
          @click="handleSend"
        >
          {{ t('KANBAN.BULK_ACTIONS.SEND_MESSAGES') }}
        </Button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.filter-chip {
  @apply inline-flex items-center gap-1 px-2 py-1 text-xs rounded-full bg-woot-100;
}

.filter-chip button {
  @apply text-slate-500 hover:text-slate-700;
}

.progress-bar-enter-active,
.progress-bar-leave-active {
  transition: width 0.5s ease-in-out;
}

.toggle {
  @apply h-5 w-9 rounded-full appearance-none bg-slate-200 transition-colors 
    relative cursor-pointer checked:bg-woot-500;
}

.toggle:before {
  content: '';
  @apply absolute left-0.5 top-0.5 h-4 w-4 rounded-full bg-white transition-all;
}

.toggle:checked:before {
  @apply translate-x-4;
}

/* Animação para o bloco de filtros */
.filter-block-enter-active,
.filter-block-leave-active {
  transition: all 0.3s ease-out;
}

.filter-block-enter-from,
.filter-block-leave-to {
  opacity: 0;
  transform: translateY(-10px);
}
</style>
