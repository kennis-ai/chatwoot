<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  item: {
    type: Object,
    default: null,
  },
  initialStage: {
    type: String,
    default: null,
  },
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();
const { t } = useI18n();

const formData = ref({
  title: '',
  description: '',
  priority: 'medium',
  status: 'open',
  funnel_stage: '',
  conversation_display_id: null,
  custom_attributes: {},
});

const isEditing = computed(() => !!props.item);
const uiFlags = computed(() => store.getters['kanban/getUIFlags']);
const selectedFunnel = computed(() => store.getters['kanban/getSelectedFunnel']);
const stages = computed(() => selectedFunnel.value?.stages || []);

onMounted(() => {
  if (isEditing.value) {
    // Editing existing item
    formData.value = {
      title: props.item.item_details?.title || '',
      description: props.item.item_details?.description || '',
      priority: props.item.item_details?.priority || 'medium',
      status: props.item.item_details?.status || 'open',
      funnel_stage: props.item.funnel_stage,
      conversation_display_id: props.item.conversation_display_id,
      custom_attributes: props.item.custom_attributes || {},
    };
  } else if (props.initialStage) {
    // Creating new item in a specific stage
    formData.value.funnel_stage = props.initialStage;
  } else if (stages.value.length > 0) {
    // Creating new item - default to first stage
    formData.value.funnel_stage = stages.value[0];
  }
});

const handleSave = async () => {
  try {
    const payload = {
      funnel_id: props.funnelId,
      funnel_stage: formData.value.funnel_stage,
      item_details: {
        title: formData.value.title,
        description: formData.value.description,
        priority: formData.value.priority,
        status: formData.value.status,
      },
      custom_attributes: formData.value.custom_attributes,
    };

    if (formData.value.conversation_display_id) {
      payload.conversation_display_id = formData.value.conversation_display_id;
    }

    if (isEditing.value) {
      await store.dispatch('kanban/update', {
        id: props.item.id,
        ...payload,
      });
      useAlert(t('KANBAN.ITEM_UPDATED'));
    } else {
      await store.dispatch('kanban/create', payload);
      useAlert(t('KANBAN.ITEM_CREATED'));
    }

    emit('saved');
  } catch (error) {
    console.error('Error saving item:', error);
    useAlert(t('KANBAN.ERROR_SAVING'), 'error');
  }
};

const handleDelete = async () => {
  if (!confirm(t('KANBAN.CONFIRM_DELETE'))) return;

  try {
    await store.dispatch('kanban/delete', props.item.id);
    useAlert(t('KANBAN.ITEM_DELETED'));
    emit('saved');
  } catch (error) {
    console.error('Error deleting item:', error);
    useAlert(t('KANBAN.ERROR_DELETING'), 'error');
  }
};

const statusColor = computed(() => {
  const status = formData.value.status;
  return {
    won: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
    lost: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
    open: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
  }[status] || 'bg-slate-100 text-slate-800';
});

const statusIcon = computed(() => {
  const status = formData.value.status;
  return {
    won: 'i-lucide-check-circle',
    lost: 'i-lucide-x-circle',
    open: 'i-lucide-circle-dashed',
  }[status] || 'i-lucide-circle-dashed';
});

const statusText = computed(() => {
  const status = formData.value.status;
  return {
    won: t('KANBAN.STATUS.WON'),
    lost: t('KANBAN.STATUS.LOST'),
    open: t('KANBAN.STATUS.OPEN'),
  }[status] || t('KANBAN.STATUS.OPEN');
});
</script>

<template>
  <Modal
    :show="true"
    :on-close="() => emit('close')"
  >
    <div class="w-full max-w-2xl">
      <!-- Header -->
      <div class="border-b border-slate-200 p-6 dark:border-slate-700">
        <h2 class="text-xl font-semibold text-slate-900 dark:text-slate-25">
          {{ isEditing ? t('KANBAN.EDIT_ITEM') : t('KANBAN.NEW_ITEM') }}
        </h2>
      </div>

      <!-- Status Badge (if editing) -->
      <div
        v-if="isEditing"
        :class="[
          'mx-6 mt-6 flex items-center gap-2 rounded-lg p-3',
          statusColor
        ]"
      >
        <i :class="[statusIcon, 'h-5 w-5']" />
        <span class="font-semibold">{{ statusText }}</span>
      </div>

      <!-- Form -->
      <div class="space-y-4 p-6">
        <!-- Title -->
        <div>
          <label
            for="title"
            class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
          >
            {{ t('KANBAN.FORM.TITLE') }} <span class="text-red-500">*</span>
          </label>
          <input
            id="title"
            v-model="formData.title"
            type="text"
            required
            class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
            :placeholder="t('KANBAN.FORM.TITLE_PLACEHOLDER')"
          />
        </div>

        <!-- Description -->
        <div>
          <label
            for="description"
            class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
          >
            {{ t('KANBAN.FORM.DESCRIPTION') }}
          </label>
          <textarea
            id="description"
            v-model="formData.description"
            rows="4"
            class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
            :placeholder="t('KANBAN.FORM.DESCRIPTION_PLACEHOLDER')"
          />
        </div>

        <!-- Priority -->
        <div>
          <label
            for="priority"
            class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
          >
            {{ t('KANBAN.FORM.PRIORITY') }}
          </label>
          <select
            id="priority"
            v-model="formData.priority"
            class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
          >
            <option value="low">{{ t('KANBAN.PRIORITY.LOW') }}</option>
            <option value="medium">{{ t('KANBAN.PRIORITY.MEDIUM') }}</option>
            <option value="high">{{ t('KANBAN.PRIORITY.HIGH') }}</option>
            <option value="urgent">{{ t('KANBAN.PRIORITY.URGENT') }}</option>
          </select>
        </div>

        <!-- Status -->
        <div>
          <label
            for="status"
            class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
          >
            {{ t('KANBAN.FORM.STATUS') }}
          </label>
          <select
            id="status"
            v-model="formData.status"
            class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
          >
            <option value="open">{{ t('KANBAN.STATUS.OPEN') }}</option>
            <option value="won">{{ t('KANBAN.STATUS.WON') }}</option>
            <option value="lost">{{ t('KANBAN.STATUS.LOST') }}</option>
          </select>
        </div>

        <!-- Stage -->
        <div>
          <label
            for="stage"
            class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
          >
            {{ t('KANBAN.FORM.STAGE') }} <span class="text-red-500">*</span>
          </label>
          <select
            id="stage"
            v-model="formData.funnel_stage"
            required
            class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
          >
            <option
              v-for="stage in stages"
              :key="stage"
              :value="stage"
            >
              {{ stage }}
            </option>
          </select>
        </div>

        <!-- Conversation ID (Optional) -->
        <div>
          <label
            for="conversation_id"
            class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300"
          >
            {{ t('KANBAN.FORM.CONVERSATION_ID') }}
          </label>
          <input
            id="conversation_id"
            v-model.number="formData.conversation_display_id"
            type="number"
            class="w-full rounded-md border border-slate-300 px-3 py-2 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
            :placeholder="t('KANBAN.FORM.CONVERSATION_ID_PLACEHOLDER')"
          />
        </div>
      </div>

      <!-- Footer -->
      <div class="flex items-center justify-between border-t border-slate-200 p-6 dark:border-slate-700">
        <div>
          <Button
            v-if="isEditing"
            variant="clear"
            color-scheme="alert"
            size="small"
            @click="handleDelete"
          >
            {{ t('KANBAN.DELETE_ITEM') }}
          </Button>
        </div>
        <div class="flex gap-2">
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
            :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
            :disabled="!formData.title || !formData.funnel_stage"
            @click="handleSave"
          >
            {{ isEditing ? t('UPDATE') : t('CREATE') }}
          </Button>
        </div>
      </div>
    </div>
  </Modal>
</template>
