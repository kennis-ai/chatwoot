<template>
  <span
    :class="priorityClasses"
    :title="priorityLabel"
    :aria-label="priorityLabel"
    role="img"
  >
    <fluent-icon :icon="priorityIcon" :size="size" />
  </span>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  priority: {
    type: [String, Number],
    default: null,
    validator: (value) => {
      const validValues = [null, 'none', 'low', 'medium', 'high', 'urgent', 0, 1, 2, 3, 4];
      return validValues.includes(value);
    },
  },
  size: {
    type: [String, Number],
    default: 16,
  },
  showLabel: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

// Priority mapping with icons, colors, and labels
const priorityMap = {
  // String values
  none: {
    icon: 'flag',
    color: 'text-slate-400 dark:text-slate-500',
    bgColor: 'bg-slate-100 dark:bg-slate-800',
    label: 'PRIORITY.NONE',
  },
  low: {
    icon: 'flag',
    color: 'text-blue-500 dark:text-blue-400',
    bgColor: 'bg-blue-50 dark:bg-blue-900/20',
    label: 'PRIORITY.LOW',
  },
  medium: {
    icon: 'flag',
    color: 'text-yellow-500 dark:text-yellow-400',
    bgColor: 'bg-yellow-50 dark:bg-yellow-900/20',
    label: 'PRIORITY.MEDIUM',
  },
  high: {
    icon: 'flag',
    color: 'text-orange-500 dark:text-orange-400',
    bgColor: 'bg-orange-50 dark:bg-orange-900/20',
    label: 'PRIORITY.HIGH',
  },
  urgent: {
    icon: 'warning',
    color: 'text-red-600 dark:text-red-400',
    bgColor: 'bg-red-50 dark:bg-red-900/20',
    label: 'PRIORITY.URGENT',
  },
  // Numeric values (0-4)
  0: {
    icon: 'flag',
    color: 'text-slate-400 dark:text-slate-500',
    bgColor: 'bg-slate-100 dark:bg-slate-800',
    label: 'PRIORITY.NONE',
  },
  1: {
    icon: 'flag',
    color: 'text-blue-500 dark:text-blue-400',
    bgColor: 'bg-blue-50 dark:bg-blue-900/20',
    label: 'PRIORITY.LOW',
  },
  2: {
    icon: 'flag',
    color: 'text-yellow-500 dark:text-yellow-400',
    bgColor: 'bg-yellow-50 dark:bg-yellow-900/20',
    label: 'PRIORITY.MEDIUM',
  },
  3: {
    icon: 'flag',
    color: 'text-orange-500 dark:text-orange-400',
    bgColor: 'bg-orange-50 dark:bg-orange-900/20',
    label: 'PRIORITY.HIGH',
  },
  4: {
    icon: 'warning',
    color: 'text-red-600 dark:text-red-400',
    bgColor: 'bg-red-50 dark:bg-red-900/20',
    label: 'PRIORITY.URGENT',
  },
};

// Get priority configuration
const priorityConfig = computed(() => {
  return priorityMap[props.priority] || priorityMap.none;
});

// Icon to display
const priorityIcon = computed(() => {
  return priorityConfig.value.icon;
});

// CSS classes for styling
const priorityClasses = computed(() => {
  const classes = [
    'priority-icon inline-flex items-center justify-center transition-colors duration-200',
    priorityConfig.value.color,
  ];

  if (props.showLabel) {
    classes.push('gap-1.5 px-2 py-1 rounded-md', priorityConfig.value.bgColor);
  }

  return classes.join(' ');
});

// Label for tooltip and accessibility
const priorityLabel = computed(() => {
  return t(priorityConfig.value.label);
});
</script>

<style scoped>
.priority-icon:hover {
  @apply opacity-80;
}
</style>
