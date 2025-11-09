<script setup>
import { defineProps, defineEmits } from 'vue';
import ColorPicker from '../../../../components-next/colorpicker/ColorPicker.vue';

defineProps({
  modelValue: {
    type: String,
    required: true,
  },
});

const emit = defineEmits(['update:modelValue']);
</script>

<template>
  <div class="stage-color-picker" @click.stop.prevent>
    <ColorPicker
      :model-value="modelValue"
      class="!w-full"
      @update:model-value="color => emit('update:modelValue', color)"
    />
  </div>
</template>

<style lang="scss" scoped>
.stage-color-picker {
  :deep() {
    .relative {
      width: 100%;
    }

    button {
      width: 100%;
    }
  }
}
</style>
