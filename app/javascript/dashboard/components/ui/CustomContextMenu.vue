<template>
  <teleport to="body">
    <div
      v-if="show"
      class="custom-context-menu-overlay fixed inset-0 z-[9998]"
      @click="handleClose"
      @contextmenu.prevent="handleClose"
    >
      <div
        ref="menuRef"
        class="custom-context-menu absolute z-[9999]"
        :style="menuStyle"
        @click.stop
        @contextmenu.prevent.stop
      >
        <slot />
      </div>
    </div>
  </teleport>
</template>

<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  x: {
    type: Number,
    required: true,
  },
  y: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close']);

const menuRef = ref(null);

// Calculate menu position with viewport boundary detection
const menuStyle = computed(() => {
  const style = {
    position: 'fixed',
    left: `${props.x}px`,
    top: `${props.y}px`,
  };

  // Wait for menu to render to get dimensions
  if (menuRef.value) {
    const rect = menuRef.value.getBoundingClientRect();
    const padding = 10; // Safety padding from viewport edge

    // Adjust horizontal position if menu would overflow right
    if (props.x + rect.width > window.innerWidth - padding) {
      style.left = `${Math.max(padding, window.innerWidth - rect.width - padding)}px`;
    }

    // Adjust vertical position if menu would overflow bottom
    if (props.y + rect.height > window.innerHeight - padding) {
      style.top = `${Math.max(padding, window.innerHeight - rect.height - padding)}px`;
    }

    // Ensure menu doesn't go off top
    if (style.top && parseInt(style.top) < padding) {
      style.top = `${padding}px`;
    }

    // Ensure menu doesn't go off left
    if (style.left && parseInt(style.left) < padding) {
      style.left = `${padding}px`;
    }
  }

  return style;
});

// Handle close event
const handleClose = () => {
  emit('close');
};

// Handle ESC key
const handleEsc = (event) => {
  if (event.key === 'Escape' && props.show) {
    handleClose();
  }
};

// Re-calculate position when show prop changes
watch(() => props.show, async (newVal) => {
  if (newVal) {
    await nextTick();
    // Force re-render of computed style after menu is visible
    if (menuRef.value) {
      menuRef.value.style.visibility = 'hidden';
      await nextTick();
      menuRef.value.style.visibility = 'visible';
    }
  }
});

onMounted(() => {
  document.addEventListener('keydown', handleEsc);
});

onUnmounted(() => {
  document.removeEventListener('keydown', handleEsc);
});
</script>

<style scoped>
.custom-context-menu-overlay {
  background: transparent;
  cursor: default;
}

.custom-context-menu {
  pointer-events: auto;
}
</style>
