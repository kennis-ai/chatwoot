<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  visible: {
    type: Boolean,
    required: true,
  },
  item: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['move', 'open-chat', 'duplicate']);

const { t } = useI18n();

const hasConversation = computed(() => {
  return props.item?.conversation_display_id != null;
});

const handleMove = () => {
  emit('move');
};

const handleOpenChat = () => {
  if (hasConversation.value) {
    emit('open-chat', props.item);
  }
};

const handleDuplicate = () => {
  emit('duplicate', props.item);
};
</script>

<template>
  <Transition name="slide-up">
    <div
      v-if="visible"
      class="fixed bottom-0 left-0 right-0 z-50 border-t border-slate-200 bg-white px-6 py-4 shadow-lg dark:border-slate-700 dark:bg-slate-800"
    >
      <div class="mx-auto flex max-w-4xl items-center justify-center gap-4">
        <!-- Move Item Button -->
        <button
          class="flex items-center gap-2 rounded-lg bg-blue-600 px-6 py-3 text-sm font-medium text-white transition-colors hover:bg-blue-700"
          @click="handleMove"
        >
          <i class="i-lucide-move h-5 w-5" />
          <span>{{ t('KANBAN.DRAG_BAR.MOVE_ITEM') }}</span>
        </button>

        <!-- Open Chat Button -->
        <button
          :disabled="!hasConversation"
          :class="[
            'flex items-center gap-2 rounded-lg px-6 py-3 text-sm font-medium transition-colors',
            hasConversation
              ? 'bg-green-600 text-white hover:bg-green-700'
              : 'cursor-not-allowed bg-slate-300 text-slate-500 dark:bg-slate-600 dark:text-slate-400'
          ]"
          @click="handleOpenChat"
        >
          <i class="i-lucide-message-circle h-5 w-5" />
          <span>{{ t('KANBAN.DRAG_BAR.OPEN_CHAT') }}</span>
        </button>

        <!-- Duplicate Button -->
        <button
          class="flex items-center gap-2 rounded-lg bg-purple-600 px-6 py-3 text-sm font-medium text-white transition-colors hover:bg-purple-700"
          @click="handleDuplicate"
        >
          <i class="i-lucide-copy h-5 w-5" />
          <span>{{ t('KANBAN.DRAG_BAR.DUPLICATE') }}</span>
        </button>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.slide-up-enter-active,
.slide-up-leave-active {
  transition: transform 0.3s ease-out, opacity 0.3s ease-out;
}

.slide-up-enter-from {
  transform: translateY(100%);
  opacity: 0;
}

.slide-up-leave-to {
  transform: translateY(100%);
  opacity: 0;
}

.slide-up-enter-to,
.slide-up-leave-from {
  transform: translateY(0);
  opacity: 1;
}
</style>
