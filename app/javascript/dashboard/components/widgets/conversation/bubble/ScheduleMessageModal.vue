<template>
  <Modal
    v-model:show="isOpen"
    :on-close="handleClose"
    size="medium"
    :show-close-button="true"
    :close-on-backdrop-click="false"
  >
    <div class="schedule-message-modal p-6">
      <header class="modal-header mb-6">
        <h3 class="text-xl font-semibold text-slate-900 dark:text-slate-100">
          {{ editingMessage ? $t('SCHEDULE_MESSAGE.EDIT_TITLE') : $t('SCHEDULE_MESSAGE.TITLE') }}
        </h3>
        <p class="text-sm text-slate-600 dark:text-slate-400 mt-1">
          {{ $t('SCHEDULE_MESSAGE.DESCRIPTION') }}
        </p>
      </header>

      <div class="modal-body space-y-4">
        <!-- Message Content -->
        <div class="form-group">
          <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">
            {{ $t('SCHEDULE_MESSAGE.MESSAGE') }}
            <span class="text-red-500">*</span>
          </label>
          <textarea
            v-model="messageContent"
            rows="6"
            class="w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-md focus:ring-2 focus:ring-woot-500 focus:border-transparent bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100 resize-y"
            :placeholder="$t('SCHEDULE_MESSAGE.MESSAGE_PLACEHOLDER')"
            @input="validateMessage"
          />
          <p v-if="errors.message" class="text-xs text-red-500 mt-1">
            {{ errors.message }}
          </p>
          <p class="text-xs text-slate-500 dark:text-slate-400 mt-1">
            {{ messageContent.length }} / {{ maxMessageLength }} {{ $t('SCHEDULE_MESSAGE.CHARACTERS') }}
          </p>
        </div>

        <!-- Schedule Date/Time -->
        <div class="form-group">
          <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">
            {{ $t('SCHEDULE_MESSAGE.SCHEDULE_TIME') }}
            <span class="text-red-500">*</span>
          </label>
          <input
            v-model="scheduledTime"
            type="datetime-local"
            :min="minDateTime"
            class="w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-md focus:ring-2 focus:ring-woot-500 focus:border-transparent bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100"
            @change="validateDateTime"
          />
          <p v-if="errors.datetime" class="text-xs text-red-500 mt-1">
            {{ errors.datetime }}
          </p>
          <p v-else class="text-xs text-slate-500 dark:text-slate-400 mt-1">
            {{ $t('SCHEDULE_MESSAGE.MIN_TIME_NOTICE') }}
          </p>
        </div>

        <!-- Preview -->
        <div v-if="isValid && scheduledTime" class="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-md p-3">
          <p class="text-sm text-blue-800 dark:text-blue-200">
            <fluent-icon icon="calendar" size="16" class="inline mr-1" />
            {{ $t('SCHEDULE_MESSAGE.WILL_SEND_AT') }}: <strong>{{ formattedDateTime }}</strong>
          </p>
        </div>
      </div>

      <footer class="modal-footer flex justify-end gap-2 mt-6 pt-4 border-t border-slate-200 dark:border-slate-700">
        <button
          class="px-4 py-2 text-sm font-medium text-slate-700 dark:text-slate-300 bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-600 rounded-md hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
          @click="handleClose"
        >
          {{ $t('SCHEDULE_MESSAGE.CANCEL') }}
        </button>
        <button
          class="px-4 py-2 text-sm font-medium text-white bg-woot-500 rounded-md hover:bg-woot-600 disabled:bg-slate-300 dark:disabled:bg-slate-700 disabled:cursor-not-allowed transition-colors"
          :disabled="!isValid || isSubmitting"
          @click="handleSubmit"
        >
          <span v-if="isSubmitting" class="flex items-center gap-2">
            <fluent-icon icon="spinner" size="16" class="animate-spin" />
            {{ $t('SCHEDULE_MESSAGE.SCHEDULING') }}
          </span>
          <span v-else>
            {{ editingMessage ? $t('SCHEDULE_MESSAGE.UPDATE') : $t('SCHEDULE_MESSAGE.SCHEDULE') }}
          </span>
        </button>
      </footer>
    </div>
  </Modal>
</template>

<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import Modal from 'dashboard/components/Modal.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  conversationId: {
    type: [Number, String],
    required: true,
  },
  editingMessage: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['close', 'scheduled']);

const { t } = useI18n();

// State
const isOpen = ref(props.show);
const messageContent = ref('');
const scheduledTime = ref('');
const isSubmitting = ref(false);
const errors = ref({
  message: '',
  datetime: '',
});

// Constants
const maxMessageLength = 5000;
const minMinutesFromNow = 5;

// Helper to format datetime for input
const formatDateTimeLocal = (date) => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');
  return `${year}-${month}-${day}T${hours}:${minutes}`;
};

// Helper to add minutes to date
const addMinutes = (date, minutes) => {
  return new Date(date.getTime() + minutes * 60000);
};

// Computed
const minDateTime = computed(() => {
  const now = new Date();
  const min = addMinutes(now, minMinutesFromNow);
  return formatDateTimeLocal(min);
});

const formattedDateTime = computed(() => {
  if (!scheduledTime.value) return '';
  try {
    const date = new Date(scheduledTime.value);
    return date.toLocaleString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      hour12: true
    });
  } catch {
    return scheduledTime.value;
  }
});

const isValid = computed(() => {
  return (
    messageContent.value.trim().length > 0 &&
    messageContent.value.length <= maxMessageLength &&
    scheduledTime.value &&
    !errors.value.message &&
    !errors.value.datetime
  );
});

// Methods
const validateMessage = () => {
  errors.value.message = '';

  if (messageContent.value.trim().length === 0) {
    errors.value.message = t('SCHEDULE_MESSAGE.ERRORS.MESSAGE_REQUIRED');
  } else if (messageContent.value.length > maxMessageLength) {
    errors.value.message = t('SCHEDULE_MESSAGE.ERRORS.MESSAGE_TOO_LONG', { max: maxMessageLength });
  }
};

const validateDateTime = () => {
  errors.value.datetime = '';

  if (!scheduledTime.value) {
    errors.value.datetime = t('SCHEDULE_MESSAGE.ERRORS.DATETIME_REQUIRED');
    return;
  }

  try {
    const selected = new Date(scheduledTime.value);
    const minTime = addMinutes(new Date(), minMinutesFromNow);

    if (selected < minTime) {
      errors.value.datetime = t('SCHEDULE_MESSAGE.ERRORS.DATETIME_TOO_SOON', { minutes: minMinutesFromNow });
    }
  } catch {
    errors.value.datetime = t('SCHEDULE_MESSAGE.ERRORS.DATETIME_INVALID');
  }
};

const handleClose = () => {
  if (!isSubmitting.value) {
    emit('close');
    resetForm();
  }
};

const handleSubmit = async () => {
  if (!isValid.value || isSubmitting.value) return;

  validateMessage();
  validateDateTime();

  if (errors.value.message || errors.value.datetime) return;

  isSubmitting.value = true;

  try {
    const payload = {
      message: messageContent.value.trim(),
      scheduledTime: scheduledTime.value,
      conversationId: props.conversationId,
      ...(props.editingMessage && { messageId: props.editingMessage.id }),
    };

    emit('scheduled', payload);

    // Close modal after successful schedule
    setTimeout(() => {
      handleClose();
    }, 500);
  } catch (error) {
    console.error('Failed to schedule message:', error);
    errors.value.message = t('SCHEDULE_MESSAGE.ERRORS.SCHEDULE_FAILED');
  } finally {
    isSubmitting.value = false;
  }
};

const resetForm = () => {
  messageContent.value = '';
  scheduledTime.value = '';
  errors.value = { message: '', datetime: '' };
  isSubmitting.value = false;
};

// Watchers
watch(() => props.show, (newVal) => {
  isOpen.value = newVal;
  if (newVal && props.editingMessage) {
    // Load editing message data
    messageContent.value = props.editingMessage.content || '';
    scheduledTime.value = props.editingMessage.scheduledAt || '';
  } else if (newVal) {
    resetForm();
  }
});

watch(isOpen, (newVal) => {
  if (!newVal) {
    handleClose();
  }
});

onMounted(() => {
  if (props.show) {
    isOpen.value = true;
    if (props.editingMessage) {
      messageContent.value = props.editingMessage.content || '';
      scheduledTime.value = props.editingMessage.scheduledAt || '';
    }
  }
});
</script>

<style scoped>
input[type="datetime-local"]::-webkit-calendar-picker-indicator {
  @apply cursor-pointer;
  @apply dark:filter dark:invert;
}
</style>
