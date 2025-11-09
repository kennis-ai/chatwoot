<script setup>
import { computed } from 'vue';

const props = defineProps({
  modelValue: {
    type: Boolean,
    required: true,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  size: {
    type: String,
    default: 'default',
    validator: value => ['small', 'default', 'large'].includes(value),
  },
});

const emit = defineEmits(['update:modelValue']);

const toggleClasses = computed(() => ({
  'toggle-wrapper': true,
  [`toggle-${props.size}`]: true,
  'toggle-checked': props.modelValue,
  'toggle-disabled': props.disabled,
}));

const handleToggle = () => {
  if (!props.disabled) {
    emit('update:modelValue', !props.modelValue);
  }
};
</script>

<template>
  <button
    type="button"
    :class="toggleClasses"
    :disabled="disabled"
    @click="handleToggle"
  >
    <div class="toggle-track">
      <div class="toggle-thumb" />
    </div>
  </button>
</template>

<style lang="scss" scoped>
.toggle-wrapper {
  @apply relative inline-flex items-center cursor-pointer;

  &.toggle-disabled {
    @apply cursor-not-allowed opacity-50;
  }
}

.toggle-track {
  @apply relative w-10 h-6 bg-slate-200 dark:bg-slate-700 rounded-full transition-colors;

  .toggle-checked & {
    @apply bg-woot-500;
  }
}

.toggle-thumb {
  @apply absolute left-1 top-1 w-4 h-4 bg-white rounded-full transition-transform;

  .toggle-checked & {
    @apply translate-x-4;
  }
}

// Tamanhos
.toggle-small {
  .toggle-track {
    @apply w-8 h-5;
  }

  .toggle-thumb {
    @apply w-3 h-3;
  }

  &.toggle-checked .toggle-thumb {
    @apply translate-x-3;
  }
}

.toggle-large {
  .toggle-track {
    @apply w-12 h-7;
  }

  .toggle-thumb {
    @apply w-5 h-5;
  }

  &.toggle-checked .toggle-thumb {
    @apply translate-x-5;
  }
}
</style>
