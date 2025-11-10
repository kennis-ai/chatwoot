<template>
  <svg :width="size" :height="size" :viewBox="`0 0 ${size} ${size}`" class="priority-circle">
    <circle
      :cx="size/2"
      :cy="size/2"
      :r="radius"
      :stroke="borderColor"
      stroke-width="2"
      fill="none"
    />
    <template v-for="n in filledBlocks" :key="n">
      <path
        v-bind="getArcProps(n - 1)"
        :stroke="priorityColor"
        stroke-width="2.5"
        fill="none"
        stroke-linecap="round"
      />
    </template>
  </svg>
</template>

<script setup>
import { computed } from 'vue';
const props = defineProps({
  priority: {
    type: String,
    required: true,
  },
  size: {
    type: Number,
    default: 20,
  },
});

const radius = computed(() => props.size / 2 - 2);
const borderColor = '#CBD5E1'; // slate-300

const priorityColor = computed(() => {
  switch (props.priority) {
    case 'high':
      return '#E11D48'; // ruby-600
    case 'medium':
      return '#F59E42'; // yellow-500
    case 'low':
      return '#22C55E'; // green-500
    case 'urgent':
      return '#DC2626'; // red-600
    default:
      return '#64748B'; // slate-500
  }
});

const filledBlocks = computed(() => {
  switch (props.priority) {
    case 'low':
      return 1;
    case 'medium':
      return 2;
    case 'high':
      return 3;
    case 'urgent':
      return 4;
    default:
      return 0;
  }
});

// Gera os arcos de borda para cada bloco
function getArcProps(index) {
  const r = radius.value;
  const cx = props.size / 2;
  const cy = props.size / 2;
  const startAngle = (index * 90 - 90) * (Math.PI / 180);
  const endAngle = ((index + 1) * 90 - 90) * (Math.PI / 180);
  const x1 = cx + r * Math.cos(startAngle);
  const y1 = cy + r * Math.sin(startAngle);
  const x2 = cx + r * Math.cos(endAngle);
  const y2 = cy + r * Math.sin(endAngle);
  const largeArcFlag = 0;
  return {
    d: `M${x1},${y1} A${r},${r} 0 ${largeArcFlag},1 ${x2},${y2}`,
  };
}
</script>

<style scoped>
.priority-circle {
  display: inline-block;
  vertical-align: middle;
}
</style> 