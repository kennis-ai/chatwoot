<script setup>
import { ref } from 'vue';

const props = defineProps({
  draggedItem: {
    type: Object,
    default: null,
  },
  enabled: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['quickAction']);

const draggedOverActionId = ref(null);

const quickActions = [
  {
    id: 'move',
    icon: 'arrow-right',
    color: 'blue',
    description: 'Mover Item',
    bgColorClass: '',
    borderColorClass: '',
    hoverBorderColorClass: 'hover:border-blue-700 dark:hover:border-blue-600',
    textColorClass: 'text-white',
    customHexStyle: { backgroundColor: '#3B82F6', borderColor: '#2563EB' },
  },
  {
    id: 'chat',
    icon: 'chat',
    color: 'amber',
    description: 'Abrir Chat',
    bgColorClass: 'bg-amber-100 dark:bg-amber-900',
    borderColorClass: 'border-amber-300 dark:border-amber-700',
    hoverBorderColorClass: 'hover:border-amber-500 dark:hover:border-amber-400',
    textColorClass: 'text-amber-800 dark:text-amber-200',
  },
  {
    id: 'duplicate',
    icon: 'copy',
    color: 'sky',
    description: 'Duplicar Item',
    bgColorClass: 'bg-sky-100 dark:bg-sky-900',
    borderColorClass: 'border-sky-300 dark:border-sky-700',
    hoverBorderColorClass: 'hover:border-sky-500 dark:hover:border-sky-400',
    textColorClass: 'text-sky-800 dark:text-sky-200',
  },
];

const handleDropOnAction = (actionId, event) => {
  event.preventDefault(); // Important for drop to work
  emit('quickAction', { actionId, item: props.draggedItem });
  draggedOverActionId.value = null;
};

const getButtonDynamicClasses = (action, index) => {
  const classes = [
    action.bgColorClass,
    action.borderColorClass,
    action.hoverBorderColorClass,
    action.textColorClass,
  ];

  const draggedOverIndex = quickActions.findIndex(
    a => a.id === draggedOverActionId.value
  );

  if (action.id === draggedOverActionId.value) {
    classes.push('w-[240px]');
    classes.push('scale-125');
    classes.push('shadow-xl');
  } else {
    classes.push('w-[180px]');
    classes.push('hover:scale-105');
    classes.push('hover:shadow-lg');
  }

  if (draggedOverIndex !== -1) {
    if (index === draggedOverIndex) {
      classes.push('mx-1.5');
    } else if (index === draggedOverIndex - 1) {
      classes.push('ml-1.5', 'mr-8');
    } else if (index === draggedOverIndex + 1) {
      classes.push('ml-8', 'mr-1.5');
    } else {
      classes.push('mx-1.5');
    }
  } else {
    classes.push('mx-1.5');
  }

  return classes;
};

const handleDragEnterAction = actionId => {
  draggedOverActionId.value = actionId;
};

const handleDragLeaveAction = actionId => {
  if (draggedOverActionId.value === actionId) {
    draggedOverActionId.value = null;
  }
};
</script>

<template>
  <div
    v-if="enabled"
    class="fixed bottom-0 left-0 right-0 flex justify-center z-50 p-4"
  >
    <div
      class="dragbar-content shadow-2xl rounded-xl border border-slate-200 dark:border-slate-700 p-4 transition-all duration-300 ease-in-out"
    >
      <div class="flex justify-center items-center">
        <button
          v-for="(action, index) in quickActions"
          :key="action.id"
          class="dragbar-action-btn flex flex-col items-center justify-center p-3 rounded-lg transition-all duration-300 ease-in-out transform border h-[70px] shadow-md"
          :class="getButtonDynamicClasses(action, index)"
          :style="action.customHexStyle ? action.customHexStyle : null"
          @dragover.prevent
          @dragenter="handleDragEnterAction(action.id)"
          @dragleave="handleDragLeaveAction(action.id)"
          @drop="handleDropOnAction(action.id, $event)"
        >
          <fluent-icon
            :icon="action.icon"
            size="24"
            class="mb-1 pointer-events-none"
            :class="action.textColorClass"
          />
          <span class="text-xs font-medium text-center pointer-events-none">{{
            action.description
          }}</span>
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.dragbar-content {
  background-color: rgba(255, 255, 255, 0.25); /* 25% opaque white */
  backdrop-filter: blur(4px); /* Reduced blur */
  -webkit-backdrop-filter: blur(4px); /* Reduced blur for Safari */
}

@media (prefers-color-scheme: dark) {
  .dragbar-content {
    background-color: rgba(
      51,
      65,
      85,
      0.25
    ) !important; /* slate-700 @ 25% opacity for dark mode */
  }
}

.dragbar-action-btn {
  /* Base styles for the button, colors are now dynamic via :class */
}

.dragbar-action-btn:hover {
  /* Hover styles are mostly handled by Tailwind classes */
}

.dragbar-action-btn:active {
  @apply transform scale-100 shadow-md; /* Slightly less scale on active */
}

/* Style to indicate drop zone during drag over - optional */
.dragbar-action-btn.dragover-active {
  @apply ring-2 ring-woot-500 ring-offset-4 ring-offset-current;
}
</style>
