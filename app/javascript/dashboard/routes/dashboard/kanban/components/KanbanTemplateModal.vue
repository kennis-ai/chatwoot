<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  template: {
    type: Object,
    default: null,
  },
  funnelId: {
    type: Number,
    required: true,
  },
  stage: {
    type: String,
    default: null,
  },
  funnel: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();

const formData = ref({
  title: '',
  message: '',
  enabled: true,
  funnel_id: props.funnelId,
  stage: '',
  webhook_enabled: false,
  conditions_enabled: false,
});

const isEditing = computed(() => !!props.template);

onMounted(() => {
  if (isEditing.value) {
    formData.value = {
      title: props.template.title || '',
      message: props.template.message || '',
      enabled: props.template.enabled !== false,
      funnel_id: props.template.funnel_id || props.funnelId,
      stage: props.template.stage || props.stage || '',
      webhook_enabled: props.template.webhook_enabled || false,
      conditions_enabled: props.template.conditions_enabled || false,
    };
  } else if (props.stage) {
    formData.value.stage = props.stage;
  }
});

const handleSave = () => {
  if (!formData.value.title.trim() || !formData.value.message.trim() || !formData.value.stage) {
    return;
  }

  const templateData = {
    ...formData.value,
    created_at: props.template?.created_at || new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  emit('saved', templateData);
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
        <h2 class="text-xl font-semibold text-slate-900 dark:text-slate-25">
          {{ isEditing ? t('KANBAN.TEMPLATES.EDIT_TEMPLATE') : t('KANBAN.TEMPLATES.ADD_TEMPLATE') }}
        </h2>
      </div>

      <!-- Form -->
      <div class="p-6">
        <div class="grid grid-cols-2 gap-6">
          <!-- Left Column: Configuration -->
          <div class="space-y-4">
            <h3 class="text-sm font-semibold text-slate-700 dark:text-slate-300">
              {{ t('KANBAN.TEMPLATES.FUNNEL_INFO') }}
            </h3>

            <!-- Message Template Toggle -->
            <div class="flex items-center gap-3">
              <label class="relative inline-flex cursor-pointer items-center">
                <input
                  v-model="formData.enabled"
                  type="checkbox"
                  class="peer sr-only"
                />
                <div class="peer h-6 w-11 rounded-full bg-slate-200 after:absolute after:left-[2px] after:top-[2px] after:h-5 after:w-5 after:rounded-full after:border after:border-slate-300 after:bg-white after:transition-all after:content-[''] peer-checked:bg-blue-600 peer-checked:after:translate-x-full peer-checked:after:border-white peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-blue-300 dark:border-slate-600 dark:bg-slate-700 dark:peer-focus:ring-blue-800"></div>
              </label>
              <span class="text-sm font-medium text-slate-700 dark:text-slate-300">
                {{ t('KANBAN.TEMPLATES.DEFAULT_MESSAGE') }}
              </span>
            </div>

            <!-- Stage Selector -->
            <div>
              <label
                for="stage"
                class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
              >
                {{ t('KANBAN.TEMPLATES.STAGE') }}
              </label>
              <select
                id="stage"
                v-model="formData.stage"
                required
                class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
              >
                <option
                  v-for="stageOption in funnel.stages"
                  :key="stageOption"
                  :value="stageOption"
                >
                  {{ stageOption }}
                </option>
              </select>
            </div>

            <!-- Basic Information -->
            <h3 class="mt-6 text-sm font-semibold text-slate-700 dark:text-slate-300">
              {{ t('KANBAN.TEMPLATES.BASIC_INFO') }}
            </h3>

            <!-- Title -->
            <div>
              <label
                for="title"
                class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
              >
                {{ t('KANBAN.TEMPLATES.TEMPLATE_TITLE') }}
              </label>
              <input
                id="title"
                v-model="formData.title"
                type="text"
                required
                class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
                :placeholder="t('KANBAN.TEMPLATES.TEMPLATE_TITLE_PLACEHOLDER')"
              />
            </div>

            <!-- Additional Options -->
            <div class="space-y-3 pt-4">
              <!-- Webhook Toggle -->
              <div class="flex items-center gap-3">
                <label class="relative inline-flex cursor-pointer items-center">
                  <input
                    v-model="formData.webhook_enabled"
                    type="checkbox"
                    class="peer sr-only"
                  />
                  <div class="peer h-6 w-11 rounded-full bg-slate-200 after:absolute after:left-[2px] after:top-[2px] after:h-5 after:w-5 after:rounded-full after:border after:border-slate-300 after:bg-white after:transition-all after:content-[''] peer-checked:bg-blue-600 peer-checked:after:translate-x-full peer-checked:after:border-white peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-blue-300 dark:border-slate-600 dark:bg-slate-700 dark:peer-focus:ring-blue-800"></div>
                </label>
                <span class="text-sm text-slate-700 dark:text-slate-300">
                  {{ t('KANBAN.TEMPLATES.WEBHOOK') }}
                </span>
              </div>

              <!-- Conditions Toggle -->
              <div class="flex items-center gap-3">
                <label class="relative inline-flex cursor-pointer items-center">
                  <input
                    v-model="formData.conditions_enabled"
                    type="checkbox"
                    class="peer sr-only"
                  />
                  <div class="peer h-6 w-11 rounded-full bg-slate-200 after:absolute after:left-[2px] after:top-[2px] after:h-5 after:w-5 after:rounded-full after:border after:border-slate-300 after:bg-white after:transition-all after:content-[''] peer-checked:bg-blue-600 peer-checked:after:translate-x-full peer-checked:after:border-white peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-blue-300 dark:border-slate-600 dark:bg-slate-700 dark:peer-focus:ring-blue-800"></div>
                </label>
                <span class="text-sm text-slate-700 dark:text-slate-300">
                  {{ t('KANBAN.TEMPLATES.CONDITIONS') }}
                </span>
              </div>
            </div>
          </div>

          <!-- Right Column: Message Editor -->
          <div class="space-y-2">
            <label
              for="message"
              class="block text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.TEMPLATES.MESSAGE') }}
            </label>

            <!-- Simple Toolbar -->
            <div class="flex gap-1 rounded-t-md border border-b-0 border-slate-300 bg-slate-50 p-2 dark:border-slate-600 dark:bg-slate-800">
              <button
                type="button"
                class="rounded px-2 py-1 text-slate-600 hover:bg-slate-200 dark:text-slate-400 dark:hover:bg-slate-700"
                @click="() => {}"
              >
                <i class="i-lucide-bold h-4 w-4" />
              </button>
              <button
                type="button"
                class="rounded px-2 py-1 text-slate-600 hover:bg-slate-200 dark:text-slate-400 dark:hover:bg-slate-700"
                @click="() => {}"
              >
                <i class="i-lucide-italic h-4 w-4" />
              </button>
              <button
                type="button"
                class="rounded px-2 py-1 text-slate-600 hover:bg-slate-200 dark:text-slate-400 dark:hover:bg-slate-700"
                @click="() => {}"
              >
                <i class="i-lucide-strikethrough h-4 w-4" />
              </button>
              <div class="mx-2 w-px bg-slate-300 dark:bg-slate-600"></div>
              <button
                type="button"
                class="rounded px-2 py-1 text-slate-600 hover:bg-slate-200 dark:text-slate-400 dark:hover:bg-slate-700"
                @click="() => {}"
              >
                <i class="i-lucide-list h-4 w-4" />
              </button>
              <button
                type="button"
                class="rounded px-2 py-1 text-slate-600 hover:bg-slate-200 dark:text-slate-400 dark:hover:bg-slate-700"
                @click="() => {}"
              >
                <i class="i-lucide-list-ordered h-4 w-4" />
              </button>
              <button
                type="button"
                class="rounded px-2 py-1 text-slate-600 hover:bg-slate-200 dark:text-slate-400 dark:hover:bg-slate-700"
                @click="() => {}"
              >
                <i class="i-lucide-link h-4 w-4" />
              </button>
            </div>

            <!-- Message Textarea -->
            <textarea
              id="message"
              v-model="formData.message"
              rows="16"
              required
              class="w-full rounded-b-md border border-slate-300 px-3 py-2 font-mono text-sm dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
              :placeholder="t('KANBAN.TEMPLATES.MESSAGE_PLACEHOLDER')"
            />
          </div>
        </div>
      </div>

      <!-- Footer -->
      <div class="flex items-center justify-end gap-2 border-t border-slate-200 p-6 dark:border-slate-700">
        <Button
          variant="clear"
          size="small"
          @click="emit('close')"
        >
          {{ t('CANCEL') }}
        </Button>
        <Button
          variant="primary"
          size="small"
          :disabled="!formData.title || !formData.message || !formData.stage"
          @click="handleSave"
        >
          {{ t('SAVE') }}
        </Button>
      </div>
    </div>
  </Modal>
</template>
