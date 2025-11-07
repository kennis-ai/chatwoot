<script setup>
import { ref } from 'vue';
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
});

const emit = defineEmits(['close', 'updated']);

const { t } = useI18n();
const store = useStore();

const isUpdating = ref(false);

const updateStatus = async (status) => {
  isUpdating.value = true;

  try {
    await store.dispatch('kanban/update', {
      id: props.item.id,
      item_details: {
        ...props.item.item_details,
        status,
      },
    });

    useAlert(t('KANBAN.STATUS_UPDATED'));
    emit('updated');
  } catch (error) {
    console.error('Error updating status:', error);
    useAlert(t('KANBAN.ERROR_UPDATING_STATUS'), 'error');
  } finally {
    isUpdating.value = false;
  }
};
</script>

<template>
  <Modal
    :show="true"
    :on-close="() => emit('close')"
  >
    <div class="w-full max-w-md">
      <!-- Header -->
      <div class="border-b border-slate-200 p-6 dark:border-slate-700">
        <h2 class="text-xl font-semibold text-slate-900 dark:text-slate-25">
          {{ t('KANBAN.UPDATE_STATUS') }}
        </h2>
      </div>

      <!-- Content -->
      <div class="p-6">
        <div class="grid grid-cols-2 gap-4">
          <!-- Won Button -->
          <button
            @click="updateStatus('won')"
            :disabled="isUpdating"
            class="flex flex-col items-center gap-3 rounded-lg border-2 border-green-200 bg-green-50 p-6 transition-all hover:border-green-400 hover:bg-green-100 disabled:opacity-50 dark:border-green-800 dark:bg-green-900/20 dark:hover:border-green-600"
          >
            <i class="i-lucide-check-circle h-12 w-12 text-green-600 dark:text-green-400" />
            <span class="text-lg font-semibold text-green-800 dark:text-green-300">
              {{ t('KANBAN.STATUS.WON') }}
            </span>
          </button>

          <!-- Lost Button -->
          <button
            @click="updateStatus('lost')"
            :disabled="isUpdating"
            class="flex flex-col items-center gap-3 rounded-lg border-2 border-red-200 bg-red-50 p-6 transition-all hover:border-red-400 hover:bg-red-100 disabled:opacity-50 dark:border-red-800 dark:bg-red-900/20 dark:hover:border-red-600"
          >
            <i class="i-lucide-x-circle h-12 w-12 text-red-600 dark:text-red-400" />
            <span class="text-lg font-semibold text-red-800 dark:text-red-300">
              {{ t('KANBAN.STATUS.LOST') }}
            </span>
          </button>
        </div>
      </div>

      <!-- Footer -->
      <div class="flex items-center justify-end border-t border-slate-200 p-6 dark:border-slate-700">
        <Button
          variant="clear"
          size="small"
          @click="emit('close')"
        >
          {{ t('CANCEL') }}
        </Button>
      </div>
    </div>
  </Modal>
</template>
