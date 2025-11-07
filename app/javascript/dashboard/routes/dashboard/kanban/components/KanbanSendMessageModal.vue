<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close', 'sent']);

const { t } = useI18n();
const store = useStore();

const selectedTemplate = ref(null);
const customMessage = ref('');
const isSending = ref(false);

const config = computed(() => store.getters['kanban/getConfig']);
const templates = computed(() => {
  if (!config.value?.funnels) return [];

  const funnel = config.value.funnels.find(f => f.id === props.funnelId);
  if (!funnel?.templates) return [];

  return funnel.templates;
});

const contactInfo = computed(() => {
  const details = props.item.item_details || {};
  return {
    name: details.title || t('KANBAN.SEND_MESSAGE.UNKNOWN_CONTACT'),
    phone: details.phone || '-',
    channel: details.channel || 'WhatsApp',
    status: details.status || 'open',
    conversationId: props.item.conversation_display_id || '-',
  };
});

const statusConfig = computed(() => {
  const configs = {
    open: {
      color: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
      label: t('KANBAN.STATUS.OPEN'),
    },
    won: {
      color:
        'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
      label: t('KANBAN.STATUS.WON'),
    },
    lost: {
      color: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
      label: t('KANBAN.STATUS.LOST'),
    },
  };
  return configs[contactInfo.value.status] || configs.open;
});

const messageToSend = computed(() => {
  if (selectedTemplate.value) {
    return (
      templates.value.find(tmpl => tmpl.id === selectedTemplate.value)
        ?.message || ''
    );
  }
  return customMessage.value;
});

const selectTemplate = templateId => {
  selectedTemplate.value = templateId;
  const template = templates.value.find(tmpl => tmpl.id === templateId);
  if (template) {
    customMessage.value = template.message;
  }
};

const clearTemplate = () => {
  selectedTemplate.value = null;
};

const sendMessage = async () => {
  if (!messageToSend.value.trim()) {
    useAlert(t('KANBAN.SEND_MESSAGE.EMPTY_MESSAGE'), 'error');
    return;
  }

  if (!props.item.conversation_display_id) {
    useAlert(t('KANBAN.SEND_MESSAGE.NO_CONVERSATION'), 'error');
    return;
  }

  isSending.value = true;

  try {
    const conversationId = props.item.conversation_display_id;

    // Send message via Chatwoot API
    await store.dispatch('sendMessage', {
      conversationId,
      message: messageToSend.value,
    });

    useAlert(t('KANBAN.SEND_MESSAGE.SUCCESS'));
    emit('sent');
  } catch (error) {
    // Error already handled by store
    useAlert(t('KANBAN.SEND_MESSAGE.ERROR'), 'error');
  } finally {
    isSending.value = false;
  }
};
</script>

<template>
  <Modal show :on-close="() => emit('close')">
    <div class="w-full max-w-2xl">
      <!-- Header -->
      <div class="border-b border-slate-200 p-6 dark:border-slate-700">
        <h2 class="text-xl font-semibold text-slate-900 dark:text-slate-25">
          {{ t('KANBAN.SEND_MESSAGE.TITLE') }}
        </h2>
      </div>

      <!-- Content -->
      <div class="p-6">
        <!-- Contact Information Card -->
        <div
          class="mb-6 rounded-lg border border-slate-200 bg-slate-50 p-4 dark:border-slate-700 dark:bg-slate-800"
        >
          <div class="grid grid-cols-2 gap-4">
            <div>
              <div class="mb-3">
                <span
                  class="text-xs font-medium text-slate-500 dark:text-slate-400"
                >
                  {{ t('KANBAN.SEND_MESSAGE.CONTACT_NAME') }}
                </span>
                <p
                  class="text-sm font-semibold text-slate-900 dark:text-slate-25"
                >
                  {{ contactInfo.name }}
                </p>
              </div>

              <div class="mb-3">
                <span
                  class="text-xs font-medium text-slate-500 dark:text-slate-400"
                >
                  {{ t('KANBAN.SEND_MESSAGE.PHONE') }}
                </span>
                <p class="text-sm text-slate-700 dark:text-slate-300">
                  {{ contactInfo.phone }}
                </p>
              </div>
            </div>

            <div>
              <div class="mb-3">
                <span
                  class="text-xs font-medium text-slate-500 dark:text-slate-400"
                >
                  {{ t('KANBAN.SEND_MESSAGE.CHANNEL') }}
                </span>
                <p class="text-sm text-slate-700 dark:text-slate-300">
                  {{ contactInfo.channel }}
                </p>
              </div>

              <div class="mb-3">
                <span
                  class="text-xs font-medium text-slate-500 dark:text-slate-400"
                >
                  {{ t('KANBAN.SEND_MESSAGE.STATUS') }}
                </span>
                <span
                  :class="statusConfig.color"
                  class="inline-block rounded-full px-2 py-0.5 text-xs font-medium"
                >
                  {{ statusConfig.label }}
                </span>
              </div>

              <div>
                <span
                  class="text-xs font-medium text-slate-500 dark:text-slate-400"
                >
                  {{ t('KANBAN.SEND_MESSAGE.CONVERSATION_ID') }}
                </span>
                <p class="text-sm text-slate-700 dark:text-slate-300">
                  #{{ contactInfo.conversationId }}
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Template Selector -->
        <div v-if="templates.length > 0" class="mb-4">
          <label
            class="mb-2 block text-sm font-medium text-slate-700 dark:text-slate-300"
          >
            {{ t('KANBAN.SEND_MESSAGE.SELECT_TEMPLATE') }}
          </label>
          <select
            v-model="selectedTemplate"
            class="w-full rounded-md border border-slate-300 px-3 py-2 text-sm dark:border-slate-600 dark:bg-slate-800"
            @change="selectTemplate($event.target.value)"
          >
            <option :value="null">
              {{ t('KANBAN.SEND_MESSAGE.CUSTOM_MESSAGE') }}
            </option>
            <option
              v-for="template in templates"
              :key="template.id"
              :value="template.id"
            >
              {{ template.title }}
            </option>
          </select>
        </div>

        <!-- Message Textarea -->
        <div class="mb-4">
          <div class="mb-2 flex items-center justify-between">
            <label
              class="text-sm font-medium text-slate-700 dark:text-slate-300"
            >
              {{ t('KANBAN.SEND_MESSAGE.MESSAGE') }}
            </label>
            <button
              v-if="selectedTemplate"
              class="text-xs text-blue-600 hover:text-blue-700 dark:text-blue-400"
              @click="clearTemplate"
            >
              {{ t('KANBAN.SEND_MESSAGE.CLEAR_TEMPLATE') }}
            </button>
          </div>
          <textarea
            v-model="customMessage"
            :placeholder="t('KANBAN.SEND_MESSAGE.MESSAGE_PLACEHOLDER')"
            rows="6"
            class="w-full rounded-md border border-slate-300 px-3 py-2 text-sm dark:border-slate-600 dark:bg-slate-800"
          />
        </div>
      </div>

      <!-- Footer -->
      <div
        class="flex items-center justify-end gap-2 border-t border-slate-200 p-6 dark:border-slate-700"
      >
        <Button variant="clear" size="small" @click="emit('close')">
          {{ t('CANCEL') }}
        </Button>
        <Button
          variant="primary"
          size="small"
          :is-loading="isSending"
          :disabled="!messageToSend.trim() || !item.conversation_display_id"
          @click="sendMessage"
        >
          {{ t('KANBAN.SEND_MESSAGE.SEND') }}
        </Button>
      </div>
    </div>
  </Modal>
</template>
