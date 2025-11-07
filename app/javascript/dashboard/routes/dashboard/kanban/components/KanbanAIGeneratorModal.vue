<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';

const props = defineProps({
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close', 'generated']);

const store = useStore();
const { t } = useI18n();

const formData = ref({
  source: 'contacts', // 'contacts' or 'conversations'
  funnel_id: props.funnelId,
  max_items: 10,
  filters: {
    date_range: 'last_30_days',
    status: 'all',
  },
});

const isGenerating = ref(false);
const generatedItems = ref([]);
const step = ref(1); // 1 = config, 2 = preview, 3 = success

const selectedFunnel = computed(() => store.getters['kanban/getSelectedFunnel']);
const config = computed(() => store.getters['kanban/getConfig']);

const hasOpenAIKey = computed(() => {
  return !!config.value?.config?.openai_api_key;
});

onMounted(() => {
  if (!hasOpenAIKey.value) {
    useAlert(t('KANBAN.AI.NO_API_KEY'), 'warning');
  }
});

const handleGenerate = async () => {
  isGenerating.value = true;

  try {
    // Call AI generation endpoint
    const response = await store.dispatch('kanban/generateWithAI', {
      funnel_id: formData.value.funnel_id,
      source: formData.value.source,
      max_items: formData.value.max_items,
      filters: formData.value.filters,
    });

    generatedItems.value = response.items || [];
    step.value = 2; // Move to preview step
  } catch (error) {
    console.error('Error generating items with AI:', error);
    useAlert(t('KANBAN.AI.ERROR_GENERATING'), 'error');
  } finally {
    isGenerating.value = false;
  }
};

const handleConfirmGeneration = async () => {
  try {
    // Create all generated items
    const promises = generatedItems.value.map(item =>
      store.dispatch('kanban/create', {
        funnel_id: formData.value.funnel_id,
        funnel_stage: item.funnel_stage,
        item_details: item.item_details,
        conversation_display_id: item.conversation_display_id,
        custom_attributes: item.custom_attributes || {},
      })
    );

    await Promise.all(promises);

    step.value = 3; // Move to success step
    useAlert(t('KANBAN.AI.ITEMS_GENERATED', { count: generatedItems.value.length }));

    // Reload kanban items
    setTimeout(() => {
      emit('generated');
    }, 1500);
  } catch (error) {
    console.error('Error creating generated items:', error);
    useAlert(t('KANBAN.AI.ERROR_CREATING'), 'error');
  }
};

const getPriorityColor = (priority) => {
  return {
    urgent: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
    high: 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200',
    medium: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200',
    low: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
  }[priority] || 'bg-slate-100 text-slate-800';
};

const getPriorityIcon = (priority) => {
  return {
    urgent: 'i-lucide-alert-circle',
    high: 'i-lucide-arrow-up',
    medium: 'i-lucide-minus',
    low: 'i-lucide-arrow-down',
  }[priority] || 'i-lucide-minus';
};
</script>

<template>
  <Modal
    :show="true"
    :on-close="() => emit('close')"
  >
    <div class="w-full max-w-4xl">
      <!-- Header -->
      <div class="border-b border-slate-200 p-6 dark:border-slate-700">
        <div class="flex items-center gap-3">
          <div class="flex h-12 w-12 items-center justify-center rounded-lg bg-purple-100 dark:bg-purple-900">
            <i class="i-lucide-sparkles h-6 w-6 text-purple-600 dark:text-purple-300" />
          </div>
          <div>
            <h2 class="text-xl font-semibold text-slate-900 dark:text-slate-25">
              {{ t('KANBAN.AI.TITLE') }}
            </h2>
            <p class="text-sm text-slate-600 dark:text-slate-400">
              {{ t('KANBAN.AI.SUBTITLE') }}
            </p>
          </div>
        </div>
      </div>

      <!-- Step 1: Configuration -->
      <div
        v-if="step === 1"
        class="p-6"
      >
        <div class="space-y-6">
          <!-- API Key Warning -->
          <div
            v-if="!hasOpenAIKey"
            class="rounded-lg border border-yellow-200 bg-yellow-50 p-4 dark:border-yellow-800 dark:bg-yellow-900/20"
          >
            <div class="flex items-start gap-3">
              <i class="i-lucide-alert-triangle h-5 w-5 text-yellow-600 dark:text-yellow-400" />
              <div>
                <p class="font-medium text-yellow-800 dark:text-yellow-300">
                  {{ t('KANBAN.AI.NO_API_KEY') }}
                </p>
                <p class="mt-1 text-sm text-yellow-700 dark:text-yellow-400">
                  {{ t('KANBAN.AI.NO_API_KEY_DESCRIPTION') }}
                </p>
              </div>
            </div>
          </div>

          <!-- Source Selection -->
          <div>
            <label class="mb-3 block text-sm font-medium text-slate-700 dark:text-slate-300">
              {{ t('KANBAN.AI.DATA_SOURCE') }}
            </label>
            <div class="grid grid-cols-2 gap-4">
              <button
                @click="formData.source = 'contacts'"
                :class="[
                  'flex flex-col items-center gap-3 rounded-lg border-2 p-6 transition-all',
                  formData.source === 'contacts'
                    ? 'border-blue-600 bg-blue-50 dark:border-blue-400 dark:bg-blue-900/20'
                    : 'border-slate-200 bg-white hover:border-slate-300 dark:border-slate-700 dark:bg-slate-800'
                ]"
              >
                <i class="i-lucide-users h-8 w-8 text-blue-600 dark:text-blue-400" />
                <div class="text-center">
                  <p class="font-semibold text-slate-900 dark:text-slate-25">
                    {{ t('KANBAN.AI.SOURCE_CONTACTS') }}
                  </p>
                  <p class="mt-1 text-xs text-slate-600 dark:text-slate-400">
                    {{ t('KANBAN.AI.SOURCE_CONTACTS_DESC') }}
                  </p>
                </div>
              </button>

              <button
                @click="formData.source = 'conversations'"
                :class="[
                  'flex flex-col items-center gap-3 rounded-lg border-2 p-6 transition-all',
                  formData.source === 'conversations'
                    ? 'border-blue-600 bg-blue-50 dark:border-blue-400 dark:bg-blue-900/20'
                    : 'border-slate-200 bg-white hover:border-slate-300 dark:border-slate-700 dark:bg-slate-800'
                ]"
              >
                <i class="i-lucide-message-circle h-8 w-8 text-blue-600 dark:text-blue-400" />
                <div class="text-center">
                  <p class="font-semibold text-slate-900 dark:text-slate-25">
                    {{ t('KANBAN.AI.SOURCE_CONVERSATIONS') }}
                  </p>
                  <p class="mt-1 text-xs text-slate-600 dark:text-slate-400">
                    {{ t('KANBAN.AI.SOURCE_CONVERSATIONS_DESC') }}
                  </p>
                </div>
              </button>
            </div>
          </div>

          <!-- Max Items -->
          <div>
            <label
              for="max-items"
              class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.AI.MAX_ITEMS') }}
            </label>
            <input
              id="max-items"
              v-model.number="formData.max_items"
              type="number"
              min="1"
              max="50"
              class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
            />
            <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
              {{ t('KANBAN.AI.MAX_ITEMS_HINT') }}
            </p>
          </div>

          <!-- Filters -->
          <div>
            <label
              for="date-range"
              class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.AI.DATE_RANGE') }}
            </label>
            <select
              id="date-range"
              v-model="formData.filters.date_range"
              class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
            >
              <option value="last_7_days">{{ t('KANBAN.AI.LAST_7_DAYS') }}</option>
              <option value="last_30_days">{{ t('KANBAN.AI.LAST_30_DAYS') }}</option>
              <option value="last_90_days">{{ t('KANBAN.AI.LAST_90_DAYS') }}</option>
              <option value="all_time">{{ t('KANBAN.AI.ALL_TIME') }}</option>
            </select>
          </div>
        </div>
      </div>

      <!-- Step 2: Preview Generated Items -->
      <div
        v-else-if="step === 2"
        class="p-6"
      >
        <div class="mb-4 flex items-center justify-between">
          <h3 class="font-semibold text-slate-900 dark:text-slate-25">
            {{ t('KANBAN.AI.PREVIEW_TITLE', { count: generatedItems.length }) }}
          </h3>
          <button
            @click="step = 1"
            class="text-sm text-blue-600 hover:text-blue-700 dark:text-blue-400"
          >
            {{ t('KANBAN.AI.REGENERATE') }}
          </button>
        </div>

        <div class="max-h-96 space-y-3 overflow-y-auto">
          <div
            v-for="(item, index) in generatedItems"
            :key="index"
            class="rounded-lg border border-slate-200 bg-white p-4 dark:border-slate-700 dark:bg-slate-800"
          >
            <div class="mb-2 flex items-start justify-between">
              <h4 class="font-medium text-slate-900 dark:text-slate-25">
                {{ item.item_details.title }}
              </h4>
              <span
                :class="[
                  'flex items-center gap-1 rounded-full px-2 py-1 text-xs font-medium',
                  getPriorityColor(item.item_details.priority)
                ]"
              >
                <i :class="[getPriorityIcon(item.item_details.priority), 'h-3 w-3']" />
                {{ t(`KANBAN.PRIORITY.${item.item_details.priority.toUpperCase()}`) }}
              </span>
            </div>
            <p class="mb-2 text-sm text-slate-600 dark:text-slate-400">
              {{ item.item_details.description }}
            </p>
            <div class="flex items-center gap-2 text-xs text-slate-500">
              <span class="rounded-full bg-slate-100 px-2 py-1 dark:bg-slate-700">
                {{ item.funnel_stage }}
              </span>
              <span v-if="item.conversation_display_id">
                #{{ item.conversation_display_id }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- Step 3: Success -->
      <div
        v-else-if="step === 3"
        class="p-12 text-center"
      >
        <div class="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-green-100 dark:bg-green-900">
          <i class="i-lucide-check h-8 w-8 text-green-600 dark:text-green-300" />
        </div>
        <h3 class="mb-2 text-xl font-semibold text-slate-900 dark:text-slate-25">
          {{ t('KANBAN.AI.SUCCESS_TITLE') }}
        </h3>
        <p class="text-slate-600 dark:text-slate-400">
          {{ t('KANBAN.AI.SUCCESS_MESSAGE', { count: generatedItems.length }) }}
        </p>
      </div>

      <!-- Footer -->
      <div class="flex items-center justify-end gap-2 border-t border-slate-200 p-6 dark:border-slate-700">
        <Button
          v-if="step !== 3"
          variant="clear"
          size="small"
          @click="emit('close')"
        >
          {{ t('CANCEL') }}
        </Button>

        <Button
          v-if="step === 1"
          variant="primary"
          size="small"
          :is-loading="isGenerating"
          :disabled="!hasOpenAIKey"
          @click="handleGenerate"
        >
          <i class="i-lucide-sparkles mr-1" />
          {{ t('KANBAN.AI.GENERATE') }}
        </Button>

        <Button
          v-if="step === 2"
          variant="primary"
          size="small"
          @click="handleConfirmGeneration"
        >
          {{ t('KANBAN.AI.CONFIRM_CREATE') }}
        </Button>

        <Button
          v-if="step === 3"
          variant="primary"
          size="small"
          @click="emit('close')"
        >
          {{ t('CLOSE') }}
        </Button>
      </div>
    </div>
  </Modal>
</template>
