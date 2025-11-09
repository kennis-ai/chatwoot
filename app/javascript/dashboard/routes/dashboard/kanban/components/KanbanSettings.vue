<script setup>
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import Modal from '../../../../components/Modal.vue';
import Button from '../../../../components-next/button/Button.vue';

const props = defineProps({
  show: {
    type: Boolean,
    required: true,
  },
});
const emit = defineEmits(['close', 'dragbar-visibility-changed']);
const { t } = useI18n();
const store = useStore();

const globalWebhookEnabled = ref(false);
const webhookUrl = ref('');
const dragbarEnabled = ref(true);
const kanbanTitle = ref('Quadro Kanban');
const testStatus = ref(null);
const testLoading = ref(false);
const eventHistory = ref([]);
const activeTab = ref('preferences');
const showWebhookDetails = ref(false);

// Eventos disponíveis para webhook
const availableWebhookEvents = computed(() => [
  {
    id: 'kanban.item.created',
    label: t('KANBAN.SETTINGS.WEBHOOK_EVENTS_LIST.ITEM_CREATED.LABEL'),
    description: t(
      'KANBAN.SETTINGS.WEBHOOK_EVENTS_LIST.ITEM_CREATED.DESCRIPTION'
    ),
  },
  {
    id: 'kanban.item.updated',
    label: t('KANBAN.SETTINGS.WEBHOOK_EVENTS_LIST.ITEM_UPDATED.LABEL'),
    description: t(
      'KANBAN.SETTINGS.WEBHOOK_EVENTS_LIST.ITEM_UPDATED.DESCRIPTION'
    ),
  },
  {
    id: 'kanban.item.deleted',
    label: t('KANBAN.SETTINGS.WEBHOOK_EVENTS_LIST.ITEM_DELETED.LABEL'),
    description: t(
      'KANBAN.SETTINGS.WEBHOOK_EVENTS_LIST.ITEM_DELETED.DESCRIPTION'
    ),
  },
  {
    id: 'kanban.item.stage_changed',
    label: t('KANBAN.SETTINGS.WEBHOOK_EVENTS_LIST.STAGE_CHANGED.LABEL'),
    description: t(
      'KANBAN.SETTINGS.WEBHOOK_EVENTS_LIST.STAGE_CHANGED.DESCRIPTION'
    ),
  },
  {
    id: 'kanban.items.reordered',
    label: t('KANBAN.SETTINGS.WEBHOOK_EVENTS_LIST.ITEMS_REORDERED.LABEL'),
    description: t(
      'KANBAN.SETTINGS.WEBHOOK_EVENTS_LIST.ITEMS_REORDERED.DESCRIPTION'
    ),
  },
]);

const selectedWebhookEvents = ref([
  'kanban.item.created',
  'kanban.item.updated',
  'kanban.item.deleted',
  'kanban.item.stage_changed',
  'kanban.items.reordered',
]);

// Computed properties para acessar o store
const webhookUrlFromStore = computed(
  () => store.getters['kanban/getWebhookUrl']
);
const webhookEnabledFromStore = computed(
  () => store.getters['kanban/getWebhookEnabled']
);
const dragbarEnabledFromStore = computed(
  () => store.getters['kanban/getDragbarEnabled']
);
const kanbanTitleFromStore = computed(
  () => store.getters['kanban/getKanbanTitle']
);

const loadEventHistory = () => {
  // Por enquanto, manter histórico vazio até implementar no backend
  eventHistory.value = [];
};

onMounted(async () => {
  // Carregar configurações do store
  globalWebhookEnabled.value = webhookEnabledFromStore.value;
  webhookUrl.value = webhookUrlFromStore.value;
  dragbarEnabled.value = dragbarEnabledFromStore.value;
  kanbanTitle.value = kanbanTitleFromStore.value;
  loadEventHistory();
});

const handleClose = () => {
  emit('close');
};

const handleSave = async () => {
  try {
    await store.dispatch('kanban/updateWebhookConfig', {
      enabled: globalWebhookEnabled.value,
      webhook_url: webhookUrl.value,
      webhook_events: selectedWebhookEvents.value,
      // Incluir configurações gerais no mesmo payload
      config: {
        dragbar_enabled: dragbarEnabled.value,
        title: kanbanTitle.value,
      },
    });

    emit('dragbar-visibility-changed', dragbarEnabled.value);
    handleClose();
  } catch (error) {
    console.error('Erro ao salvar configurações:', error);
    // Aqui você pode adicionar uma notificação de erro
  }
};

const handleTestWebhook = async () => {
  testLoading.value = true;
  testStatus.value = null;

  try {
    const result = await store.dispatch('kanban/testWebhook');
    testStatus.value = {
      success: result.data.success,
      message: result.data.message || result.data.error,
    };
  } catch (error) {
    testStatus.value = {
      success: false,
      message: error.response?.data?.error || 'Erro ao testar webhook',
    };
  }

  testLoading.value = false;
  loadEventHistory();
};

const switchTab = tab => {
  activeTab.value = tab;
};

const toggleWebhookDetails = () => {
  showWebhookDetails.value = !showWebhookDetails.value;
};

const toggleWebhookEvent = eventId => {
  const index = selectedWebhookEvents.value.indexOf(eventId);
  if (index > -1) {
    selectedWebhookEvents.value.splice(index, 1);
  } else {
    selectedWebhookEvents.value.push(eventId);
  }
};

const selectAllEvents = () => {
  selectedWebhookEvents.value = availableWebhookEvents.value.map(
    event => event.id
  );
};

const deselectAllEvents = () => {
  selectedWebhookEvents.value = [];
};
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-30"
  >
    <div
      class="bg-white dark:bg-slate-900 rounded-md shadow-lg border border-slate-100 dark:border-slate-800 w-[800px] min-w-[700px] h-[600px] flex flex-col gap-0 p-0"
      style="box-shadow: 0 4px 24px 0 rgba(30, 41, 59, 0.08)"
    >
      <header
        class="flex items-center justify-between px-6 py-4 border-b border-slate-100 dark:border-slate-700"
      >
        <h3 class="text-lg font-semibold text-slate-900 dark:text-slate-100">
          {{ t('KANBAN.SETTINGS.TITLE') }}
        </h3>
        <button
          class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-300 transition-colors"
          @click="handleClose"
        >
          <svg
            class="w-5 h-5"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      </header>

      <div class="flex flex-1 overflow-hidden">
        <!-- Sidebar com tabs -->
        <div
          class="w-48 border-r border-slate-100 dark:border-slate-700 bg-slate-50 dark:bg-slate-800"
        >
          <nav class="p-4 space-y-2">
            <button
              class="w-full text-left px-4 py-3 rounded-lg text-sm font-medium transition-colors"
:class="[
                activeTab === 'preferences'
                  ? 'bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300'
                  : 'text-slate-600 hover:bg-slate-100 dark:text-slate-400 dark:hover:bg-slate-700',
              ]"
              @click="switchTab('preferences')"
            >
              Preferências
            </button>
            <button
              class="w-full text-left px-4 py-3 rounded-lg text-sm font-medium transition-colors"
:class="[
                activeTab === 'webhook'
                  ? 'bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300'
                  : 'text-slate-600 hover:bg-slate-100 dark:text-slate-400 dark:hover:bg-slate-700',
              ]"
              @click="switchTab('webhook')"
            >
              Webhook
            </button>
          </nav>
        </div>

        <!-- Conteúdo das tabs -->
        <div class="flex-1 p-6 overflow-y-auto">
          <!-- Tab Preferências -->
          <div v-if="activeTab === 'preferences'" class="space-y-6">
            <div>
              <h4
                class="text-lg font-semibold text-slate-900 dark:text-slate-100 mb-4"
              >
                {{ t('KANBAN.SETTINGS.GENERAL_SETTINGS') }}
              </h4>

              <div class="space-y-6">
                <!-- Título do Kanban -->
                <div>
                  <label
                    for="kanban-title"
                    class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2"
                  >
                    {{ t('KANBAN.SETTINGS.KANBAN_TITLE') }}
                  </label>
                  <input
                    id="kanban-title"
                    v-model="kanbanTitle"
                    type="text"
                    class="w-full px-4 py-3 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 dark:bg-slate-700 dark:border-slate-600 text-sm"
                    :placeholder="t('KANBAN.SETTINGS.KANBAN_TITLE_PLACEHOLDER')"
                    maxlength="50"
                  />
                  <p class="text-xs text-slate-500 dark:text-slate-400 mt-1">
                    {{ t('KANBAN.SETTINGS.KANBAN_TITLE_DESCRIPTION') }}
                  </p>
                </div>

                <!-- DragBar -->
                <div>
                  <div class="flex items-center gap-3">
                    <label
                      for="dragbar-enabled"
                      class="flex items-center gap-3 cursor-pointer select-none"
                    >
                      <span
                        class="relative inline-block w-11 align-middle select-none transition duration-200 ease-in"
                      >
                        <input
                          id="dragbar-enabled"
                          v-model="dragbarEnabled"
                          type="checkbox"
                          class="sr-only peer"
                        />
                        <span
                          class="block w-11 h-7 bg-slate-200 dark:bg-slate-700 rounded-full peer-checked:bg-blue-500 transition"
                        />
                        <span
                          class="dot absolute left-1 top-1 bg-white w-5 h-5 rounded-full transition peer-checked:translate-x-4"
                        />
                      </span>
                      <span
                        class="text-sm font-medium text-slate-700 dark:text-slate-300"
                      >
                        {{ t('KANBAN.SETTINGS.ENABLE_DRAGBAR') }}
                      </span>
                    </label>
                  </div>

                  <div
                    class="text-sm text-slate-600 dark:text-slate-400 mt-2 ml-14"
                  >
                    {{ t('KANBAN.SETTINGS.DRAGBAR_DESCRIPTION') }}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Tab Webhook -->
          <div v-if="activeTab === 'webhook'" class="space-y-6">
            <div>
              <h4
                class="text-lg font-semibold text-slate-900 dark:text-slate-100 mb-4"
              >
                {{ t('KANBAN.SETTINGS.TITLE') }}
              </h4>

              <div class="space-y-4">
                <div class="flex items-center gap-3">
                  <label
                    for="webhook-enabled"
                    class="flex items-center gap-3 cursor-pointer select-none"
                  >
                    <span
                      class="relative inline-block w-11 align-middle select-none transition duration-200 ease-in"
                    >
                      <input
                        id="webhook-enabled"
                        v-model="globalWebhookEnabled"
                        type="checkbox"
                        class="sr-only peer"
                      />
                      <span
                        class="block w-11 h-7 bg-slate-200 dark:bg-slate-700 rounded-full peer-checked:bg-blue-500 transition"
                      />
                      <span
                        class="dot absolute left-1 top-1 bg-white w-5 h-5 rounded-full transition peer-checked:translate-x-4"
                      />
                    </span>
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                    >
                      {{ t('KANBAN.SETTINGS.ENABLE_GLOBAL_WEBHOOK') }}
                    </span>
                  </label>
                </div>

                <div v-if="globalWebhookEnabled" class="space-y-4 pl-14">
                  <div>
                    <label
                      class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2"
                      for="webhook-url"
                    >
                      {{ t('KANBAN.SETTINGS.WEBHOOK_URL') }}
                    </label>
                    <input
                      id="webhook-url"
                      v-model="webhookUrl"
                      type="url"
                      class="w-full px-4 py-3 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 dark:bg-slate-700 dark:border-slate-600 text-sm"
                      :placeholder="
                        t('KANBAN.SETTINGS.WEBHOOK_URL_PLACEHOLDER')
                      "
                      required
                    />
                  </div>

                  <!-- Seleção de eventos -->
                  <div>
                    <div class="flex items-center justify-between mb-3">
                      <label
                        class="block text-sm font-medium text-slate-700 dark:text-slate-300"
                      >
                        {{ t('KANBAN.SETTINGS.WEBHOOK_EVENTS') }}
                      </label>
                      <span class="text-xs text-slate-500 dark:text-slate-400">
                        {{ t('KANBAN.SETTINGS.WEBHOOK_EVENTS_DESCRIPTION') }}
                      </span>
                    </div>

                    <!-- Botões de seleção rápida -->
                    <div class="flex gap-2 mb-3">
                      <Button
                        variant="outline"
                        color="slate"
                        size="small"
                        @click="selectAllEvents"
                      >
                        {{ t('KANBAN.SETTINGS.SELECT_ALL_EVENTS') }}
                      </Button>
                      <Button
                        variant="outline"
                        color="slate"
                        size="small"
                        @click="deselectAllEvents"
                      >
                        {{ t('KANBAN.SETTINGS.DESELECT_ALL_EVENTS') }}
                      </Button>
                    </div>

                    <!-- Lista de eventos -->
                    <div class="space-y-2">
                      <div
                        v-for="event in availableWebhookEvents"
                        :key="event.id"
                        class="flex items-center gap-3 p-3 bg-slate-50 dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700"
                      >
                        <input
                          :id="event.id"
                          type="checkbox"
                          :checked="selectedWebhookEvents.includes(event.id)"
                          class="w-4 h-4 text-blue-600 bg-slate-100 border-slate-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-slate-800 focus:ring-2"
                          @change="toggleWebhookEvent(event.id)"
                        />
                        <div class="flex-1">
                          <label
                            :for="event.id"
                            class="block text-sm font-medium text-slate-700 dark:text-slate-300 cursor-pointer"
                          >
                            {{ event.label }}
                          </label>
                        </div>
                        <div
                          class="text-xs text-slate-500 dark:text-slate-400 text-right max-w-xs"
                        >
                          {{ event.description }}
                        </div>
                      </div>
                    </div>
                  </div>

                  <!-- Botão para expandir/colapsar detalhes -->
                  <div class="flex items-center gap-3">
                    <Button
                      :loading="testLoading"
                      variant="outline"
                      color="blue"
                      size="small"
                      @click="handleTestWebhook"
                    >
                      {{ t('KANBAN.SETTINGS.TEST_WEBHOOK') }}
                    </Button>

                    <button
                      class="flex items-center gap-2 text-sm text-slate-600 dark:text-slate-400 hover:text-slate-800 dark:hover:text-slate-200 transition-colors"
                      @click="toggleWebhookDetails"
                    >
                      <svg
                        class="w-4 h-4 transition-transform"
                        :class="[showWebhookDetails ? 'rotate-180' : '']"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M19 9l-7 7-7-7"
                        />
                      </svg>
                      {{
                        showWebhookDetails
                          ? t('KANBAN.SETTINGS.HIDE_DETAILS')
                          : t('KANBAN.SETTINGS.SHOW_DETAILS')
                      }}
                    </button>
                  </div>

                  <!-- Status do teste -->
                  <div v-if="testStatus" class="pl-4">
                    <span
                      class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium"
                      :class="[
                        testStatus.success
                          ? 'bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300'
                          : 'bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300',
                      ]"
                    >
                      {{ testStatus.message }}
                    </span>
                  </div>

                  <!-- Detalhes colapsáveis -->
                  <div
                    v-show="showWebhookDetails"
                    class="space-y-3 pl-4 border-l-2 border-slate-200 dark:border-slate-600"
                  >
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2"
                      >
                        {{ t('KANBAN.SETTINGS.WEBHOOK_LOG') }}
                      </label>
                      <div
                        class="max-h-32 overflow-y-auto bg-slate-50 border border-slate-200 dark:bg-slate-800 dark:border-slate-700 rounded-lg p-3 text-xs"
                      >
                        <div
                          v-if="eventHistory.length === 0"
                          class="text-slate-400 dark:text-slate-400 text-center py-4 select-none bg-slate-100 dark:bg-slate-800 border border-slate-300 dark:border-slate-700 rounded"
                        >
                          {{ t('KANBAN.SETTINGS.NO_EVENTS') }}
                        </div>
                        <ul v-else class="space-y-1">
                          <li
                            v-for="(event, idx) in eventHistory"
                            :key="idx"
                            class="flex items-center gap-2"
                          >
                            <span
                              class="px-2 py-0.5 rounded text-xs font-medium"
                              :class="[
                                event.status === 'success'
                                  ? 'bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300'
                                  : 'bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300',
                              ]"
                            >
                              {{ event.status }}
                            </span>
                            <span
                              class="text-slate-700 dark:text-slate-300 truncate"
                            >
                              {{ event.event }}
                            </span>
                            <span
                              class="text-slate-500 dark:text-slate-400 ml-auto text-xs"
                            >
                              {{ event.timestamp }}
                            </span>
                          </li>
                        </ul>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <footer
        class="flex justify-end gap-3 px-6 py-4 border-t border-slate-100 dark:border-slate-700"
      >
        <Button variant="ghost" color="slate" size="small" @click="handleClose">
          {{ t('KANBAN.SETTINGS.CANCEL') }}
        </Button>
        <Button variant="solid" color="blue" size="small" @click="handleSave">
          {{ t('KANBAN.SETTINGS.SAVE') }}
        </Button>
      </footer>
    </div>
  </div>
</template>

<style lang="scss" scoped>
// Switch custom
.dot {
  transition:
    transform 0.2s,
    background 0.2s;
  background: #fff;
}
.peer:checked ~ .dot {
  transform: translateX(16px);
  background: #fff;
}
.peer:checked ~ .block {
  background: #3b82f6 !important; /* bg-blue-500 */
}
</style>
