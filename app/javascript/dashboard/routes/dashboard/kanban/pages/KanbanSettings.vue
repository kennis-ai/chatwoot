<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';

const store = useStore();
const { t } = useI18n();
const router = useRouter();

const config = computed(() => store.getters['kanban/getConfig']);
const uiFlags = computed(() => store.getters['kanban/getUIFlags']);

const formData = ref({
  enabled: true,
  funnels: [],
  webhook_url: '',
  webhook_secret: '',
  webhook_events: [],
  openai_api_key: '',
});

const newFunnel = ref({
  name: '',
  stages: [],
});

const newStageName = ref('');

onMounted(async () => {
  await store.dispatch('kanban/getConfig');

  if (config.value) {
    formData.value = {
      enabled: config.value.enabled !== false,
      funnels: JSON.parse(JSON.stringify(config.value.config?.funnels || [])),
      webhook_url: config.value.webhook_url || '',
      webhook_secret: config.value.webhook_secret || '',
      webhook_events: config.value.webhook_events || [],
      openai_api_key: config.value.config?.openai_api_key || '',
    };
  }
});

const addStage = () => {
  if (!newStageName.value.trim()) return;

  newFunnel.value.stages.push(newStageName.value.trim());
  newStageName.value = '';
};

const removeStage = (index) => {
  newFunnel.value.stages.splice(index, 1);
};

const addFunnel = () => {
  if (!newFunnel.value.name.trim() || newFunnel.value.stages.length === 0) {
    useAlert(t('KANBAN.SETTINGS.FUNNEL_VALIDATION'), 'error');
    return;
  }

  const funnel = {
    id: Date.now(), // Simple ID generation
    name: newFunnel.value.name.trim(),
    stages: [...newFunnel.value.stages],
  };

  formData.value.funnels.push(funnel);
  newFunnel.value = { name: '', stages: [] };
};

const removeFunnel = (index) => {
  if (!confirm(t('KANBAN.SETTINGS.CONFIRM_REMOVE_FUNNEL'))) return;
  formData.value.funnels.splice(index, 1);
};

const handleSave = async () => {
  try {
    const payload = {
      enabled: formData.value.enabled,
      config: {
        funnels: formData.value.funnels,
        openai_api_key: formData.value.openai_api_key || null,
      },
      webhook_url: formData.value.webhook_url || null,
      webhook_secret: formData.value.webhook_secret || null,
      webhook_events: formData.value.webhook_events || [],
    };

    if (config.value) {
      await store.dispatch('kanban/updateConfig', payload);
    } else {
      await store.dispatch('kanban/createConfig', payload);
    }

    useAlert(t('KANBAN.SETTINGS.SAVED'));
  } catch (error) {
    console.error('Error saving config:', error);
    useAlert(t('KANBAN.SETTINGS.ERROR_SAVING'), 'error');
  }
};

const navigateToBoard = () => {
  const accountId = store.getters.getCurrentAccountId;
  router.push({ name: 'kanban_board' });
};
</script>

<template>
  <div class="flex h-full flex-col">
    <!-- Header -->
    <div class="flex items-center justify-between border-b border-slate-100 p-4 dark:border-slate-700">
      <h1 class="text-2xl font-semibold text-slate-900 dark:text-slate-25">
        {{ t('KANBAN.SETTINGS.TITLE') }}
      </h1>
      <Button
        variant="clear"
        size="small"
        @click="navigateToBoard"
      >
        {{ t('KANBAN.SETTINGS.BACK_TO_BOARD') }}
      </Button>
    </div>

    <!-- Loading -->
    <div
      v-if="uiFlags.isFetching"
      class="flex h-full items-center justify-center"
    >
      <Spinner />
    </div>

    <!-- Settings Form -->
    <div
      v-else
      class="flex-1 overflow-y-auto p-6"
    >
      <div class="mx-auto max-w-4xl space-y-8">
        <!-- Enable/Disable -->
        <div class="rounded-lg border border-slate-200 p-6 dark:border-slate-700">
          <h2 class="mb-4 text-lg font-semibold text-slate-900 dark:text-slate-25">
            {{ t('KANBAN.SETTINGS.GENERAL') }}
          </h2>
          <label class="flex items-center gap-2">
            <input
              v-model="formData.enabled"
              type="checkbox"
              class="rounded border-slate-300 dark:border-slate-600"
            />
            <span class="text-sm text-slate-700 dark:text-slate-300">
              {{ t('KANBAN.SETTINGS.ENABLE_KANBAN') }}
            </span>
          </label>
        </div>

        <!-- Funnels Configuration -->
        <div class="rounded-lg border border-slate-200 p-6 dark:border-slate-700">
          <h2 class="mb-4 text-lg font-semibold text-slate-900 dark:text-slate-25">
            {{ t('KANBAN.SETTINGS.FUNNELS') }}
          </h2>

          <!-- Existing Funnels -->
          <div
            v-if="formData.funnels.length > 0"
            class="mb-6 space-y-4"
          >
            <div
              v-for="(funnel, index) in formData.funnels"
              :key="funnel.id"
              class="rounded-md border border-slate-200 p-4 dark:border-slate-600"
            >
              <div class="mb-2 flex items-center justify-between">
                <h3 class="font-medium text-slate-900 dark:text-slate-25">
                  {{ funnel.name }}
                </h3>
                <Button
                  variant="clear"
                  color-scheme="alert"
                  size="small"
                  @click="removeFunnel(index)"
                >
                  {{ t('REMOVE') }}
                </Button>
              </div>
              <div class="flex flex-wrap gap-2">
                <span
                  v-for="(stage, stageIndex) in funnel.stages"
                  :key="stageIndex"
                  class="rounded-full bg-slate-100 px-3 py-1 text-sm text-slate-700 dark:bg-slate-700 dark:text-slate-300"
                >
                  {{ stage }}
                </span>
              </div>
            </div>
          </div>

          <!-- Add New Funnel -->
          <div class="rounded-md border border-slate-200 bg-slate-50 p-4 dark:border-slate-600 dark:bg-slate-800">
            <h3 class="mb-3 font-medium text-slate-900 dark:text-slate-25">
              {{ t('KANBAN.SETTINGS.ADD_FUNNEL') }}
            </h3>

            <!-- Funnel Name -->
            <div class="mb-3">
              <label
                for="funnel-name"
                class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
              >
                {{ t('KANBAN.SETTINGS.FUNNEL_NAME') }}
              </label>
              <input
                id="funnel-name"
                v-model="newFunnel.name"
                type="text"
                class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100"
                :placeholder="t('KANBAN.SETTINGS.FUNNEL_NAME_PLACEHOLDER')"
              />
            </div>

            <!-- Stages -->
            <div class="mb-3">
              <label class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300">
                {{ t('KANBAN.SETTINGS.STAGES') }}
              </label>
              <div class="mb-2 flex gap-2">
                <input
                  v-model="newStageName"
                  type="text"
                  class="flex-1 rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100"
                  :placeholder="t('KANBAN.SETTINGS.STAGE_NAME_PLACEHOLDER')"
                  @keyup.enter="addStage"
                />
                <Button
                  variant="smooth"
                  size="small"
                  @click="addStage"
                >
                  {{ t('ADD') }}
                </Button>
              </div>
              <div
                v-if="newFunnel.stages.length > 0"
                class="flex flex-wrap gap-2"
              >
                <span
                  v-for="(stage, index) in newFunnel.stages"
                  :key="index"
                  class="inline-flex items-center gap-2 rounded-full bg-blue-100 px-3 py-1 text-sm text-blue-700 dark:bg-blue-900 dark:text-blue-300"
                >
                  {{ stage }}
                  <button
                    type="button"
                    @click="removeStage(index)"
                    class="text-blue-700 hover:text-blue-900 dark:text-blue-300 dark:hover:text-blue-100"
                  >
                    ×
                  </button>
                </span>
              </div>
            </div>

            <Button
              variant="smooth"
              size="small"
              @click="addFunnel"
            >
              {{ t('KANBAN.SETTINGS.CREATE_FUNNEL') }}
            </Button>
          </div>
        </div>

        <!-- AI Integration -->
        <div class="rounded-lg border border-slate-200 p-6 dark:border-slate-700">
          <div class="mb-4 flex items-center gap-3">
            <div class="flex h-10 w-10 items-center justify-center rounded-lg bg-purple-100 dark:bg-purple-900">
              <i class="i-lucide-sparkles h-5 w-5 text-purple-600 dark:text-purple-300" />
            </div>
            <div>
              <h2 class="text-lg font-semibold text-slate-900 dark:text-slate-25">
                {{ t('KANBAN.SETTINGS.AI_INTEGRATION') }}
              </h2>
              <p class="text-sm text-slate-600 dark:text-slate-400">
                {{ t('KANBAN.SETTINGS.AI_INTEGRATION_DESC') }}
              </p>
            </div>
          </div>
          <div>
            <label
              for="openai-api-key"
              class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.SETTINGS.OPENAI_API_KEY') }}
            </label>
            <input
              id="openai-api-key"
              v-model="formData.openai_api_key"
              type="password"
              class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
              placeholder="sk-..."
            />
            <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
              {{ t('KANBAN.SETTINGS.OPENAI_API_KEY_HINT') }}
            </p>
          </div>
        </div>

        <!-- Webhook Configuration (Optional) -->
        <div class="rounded-lg border border-slate-200 p-6 dark:border-slate-700">
          <h2 class="mb-4 text-lg font-semibold text-slate-900 dark:text-slate-25">
            {{ t('KANBAN.SETTINGS.WEBHOOKS') }}
          </h2>
          <div class="space-y-4">
            <div>
              <label
                for="webhook-url"
                class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
              >
                {{ t('KANBAN.SETTINGS.WEBHOOK_URL') }}
              </label>
              <input
                id="webhook-url"
                v-model="formData.webhook_url"
                type="url"
                class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
                placeholder="https://example.com/webhook"
              />
            </div>
            <div>
              <label
                for="webhook-secret"
                class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
              >
                {{ t('KANBAN.SETTINGS.WEBHOOK_SECRET') }}
              </label>
              <input
                id="webhook-secret"
                v-model="formData.webhook_secret"
                type="password"
                class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
                placeholder="••••••••"
              />
            </div>
          </div>
        </div>

        <!-- Save Button -->
        <div class="flex justify-end gap-2">
          <Button
            variant="clear"
            size="small"
            @click="navigateToBoard"
          >
            {{ t('CANCEL') }}
          </Button>
          <Button
            variant="primary"
            size="small"
            :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
            @click="handleSave"
          >
            {{ t('SAVE') }}
          </Button>
        </div>
      </div>
    </div>
  </div>
</template>
