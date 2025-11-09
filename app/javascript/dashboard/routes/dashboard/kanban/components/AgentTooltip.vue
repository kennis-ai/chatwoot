<script setup>
import { ref, computed, watch, nextTick, onUnmounted } from 'vue';
const props = defineProps({
  text: { type: String, default: '' },
  title: { type: String, default: '' },
  subtitle: { type: String, default: '' },
  animation: { type: String, default: 'fade' },
  zIndex: { type: [String, Number], default: 2147483647 },
  width: { type: [String, Number], default: 'max-content' },
  placement: { type: String, default: 'top' },
  align: { type: String, default: '' },
});
const show = ref(false);
const showSubtitle = ref(false);
const coords = ref(null);
const triggerRef = ref(null);
const tooltipRef = ref(null);
const containerRef = ref(null);
const offset = 0;
const tooltipAdjust = ref({ left: 0, right: '', width: '', transform: '' });
let lastShow = false;
let subtitleTimeout = null;

const updateCoords = () => {
  if (triggerRef.value) {
    const rect = triggerRef.value.getBoundingClientRect();
    coords.value = {
      left: rect.left + rect.width / 2,
      top: props.placement === 'top' ? rect.top : rect.bottom,
      triggerRect: rect, // Adiciona sempre o triggerRect para o cálculo correto
    };
    nextTick(() => {
      adjustTooltipToViewport();
    });
  }
};

function adjustTooltipToViewport() {
  if (!tooltipRef.value || !coords.value) return;
  requestAnimationFrame(() => {
    const tooltipEl = tooltipRef.value;
    const triggerEl = triggerRef.value;
    if (!tooltipEl || !triggerEl) return;
    const triggerRect = triggerEl.getBoundingClientRect();
    const tooltipRect = tooltipEl.getBoundingClientRect();
    let left = triggerRect.left + triggerRect.width / 2;
    const borderSpacing = 8;
    // Alinhamento à esquerda se align === 'left'
    if (props.align === 'left') {
      left = triggerRect.left;
      // Ajuste para alinhar verticalmente ao centro do trigger
      tooltipEl.style.top = `${
        triggerRect.top + triggerRect.height / 2 - tooltipRect.height / 2
      }px`;
      tooltipEl.style.left = `${left - tooltipRect.width - 8}px`;
      tooltipEl.style.transform = 'none';
      return;
    }
    // Só aplica ajuste se for tooltip com subtítulo
    if (props.variant === 'with-description') {
      // Se ultrapassar a esquerda
      if (left - tooltipRect.width / 2 < borderSpacing) {
        left = borderSpacing + tooltipRect.width / 2;
      }
      // Se ultrapassar a direita
      if (left + tooltipRect.width / 2 > window.innerWidth - borderSpacing) {
        left = window.innerWidth - borderSpacing - tooltipRect.width / 2;
      }
    }
    tooltipEl.style.top = `${triggerRect.top - tooltipRect.height}px`;
    tooltipEl.style.left = `${left}px`;
    tooltipEl.style.transform =
      props.align === 'left' ? 'translateX(-100%)' : 'translate(-50%, 0)';
  });
}

watch(show, val => {
  if (val) {
    if (!lastShow) {
      nextTick(() => {
        updateCoords();
        requestAnimationFrame(() => {
          adjustTooltipToViewport();
        });
        window.addEventListener('scroll', updateCoords, true);
        window.addEventListener('resize', updateCoords, true);
      });
      // Delay para animar o subtítulo após o fade do tooltip
      showSubtitle.value = false;
      if (subtitleTimeout) clearTimeout(subtitleTimeout);
      if (props.subtitle) {
        subtitleTimeout = setTimeout(() => {
          showSubtitle.value = true;
        }, 500);
      }
    }
  } else {
    window.removeEventListener('scroll', updateCoords, true);
    window.removeEventListener('resize', updateCoords, true);
    tooltipAdjust.value = { left: 0, right: '', width: '', transform: '' };
    showSubtitle.value = false;
    if (subtitleTimeout) clearTimeout(subtitleTimeout);
  }
  lastShow = val;
});
onUnmounted(() => {
  window.removeEventListener('scroll', updateCoords, true);
  window.removeEventListener('resize', updateCoords, true);
  if (subtitleTimeout) clearTimeout(subtitleTimeout);
});

const tooltipPortalStyle = computed(() => {
  if (!coords.value) return {};
  const style = {
    position: 'absolute',
    zIndex: props.zIndex,
    minWidth:
      typeof props.width === 'number' ? `${props.width}px` : props.width,
    maxWidth: 'min(320px, 90vw)',
    wordBreak: 'break-word',
    whiteSpace: 'normal',
  };
  if (tooltipAdjust.value.left !== '')
    style.left =
      typeof tooltipAdjust.value.left === 'number'
        ? tooltipAdjust.value.left + 'px'
        : tooltipAdjust.value.left;
  if (tooltipAdjust.value.right !== '') style.right = tooltipAdjust.value.right;
  if (tooltipAdjust.value.width) style.width = tooltipAdjust.value.width;
  if (tooltipAdjust.value.transform)
    style.transform = tooltipAdjust.value.transform;
  else
    style.transform =
      props.placement === 'top'
        ? 'translate(-50%, -100%)'
        : 'translate(-50%, 0%)';
  style.top = `${
    coords.value.top - (tooltipRef.value ? tooltipRef.value.offsetHeight : 0)
  }px`;
  style.left = `${
    coords.value.left +
    (triggerRef.value ? triggerRef.value.offsetWidth / 2 : 0)
  }px`;
  style.transform = 'translate(-50%, 0)';
  return style;
});
</script>

<template>
  <div ref="containerRef" class="agent-tooltip-wrapper">
    <div
      ref="triggerRef"
      class="relative"
      tabindex="0"
      @mouseenter="show = true"
      @mouseleave="show = false"
      @focus="show = true"
      @blur="show = false"
    >
      <slot />
      <teleport to="body">
        <transition :name="animation">
          <div
            v-if="show && coords"
            ref="tooltipRef"
            class="agent-tooltip-content"
            :class="{
              'with-title': title,
              'with-subtitle': subtitle,
              [`placement-${placement}`]: true,
            }"
            :style="tooltipPortalStyle"
          >
            <template v-if="title || subtitle">
              <div v-if="title" class="agent-tooltip-title">{{ title }}</div>
              <transition name="fade-subtitle">
                <div
                  v-if="showSubtitle && subtitle"
                  class="agent-tooltip-subtitle"
                >
                  {{ subtitle }}
                </div>
              </transition>
            </template>
            <template v-else>
              {{ text }}
            </template>
          </div>
        </transition>
      </teleport>
    </div>
  </div>
</template>

<style scoped>
.agent-tooltip-wrapper {
  position: relative;
  z-index: auto;
}
.agent-tooltip-content {
  background: #111;
  color: #fff;
  border-radius: 8px;
  padding: 7px 12px;
  font-size: 12px;
  font-weight: 500;
  box-shadow:
    0 4px 24px 0 rgba(0, 0, 0, 0.25),
    0 1.5px 4px 0 rgba(0, 0, 0, 0.1);
  pointer-events: none;
  white-space: normal;
  max-width: min(320px, 90vw);
  border: none;
  text-align: left;
  word-break: break-word;
}
.agent-tooltip-title {
  font-size: 13px;
  font-weight: 700;
  margin-bottom: 2px;
  color: #fff;
  opacity: 1;
  transition: opacity 0.18s cubic-bezier(0.4, 0, 0.2, 1);
}
.agent-tooltip-subtitle {
  font-size: 12px;
  font-weight: 400;
  color: #e5e5e5;
  opacity: 1;
  transition: opacity 0.22s cubic-bezier(0.42, 0, 0.58, 1);
  word-break: break-word;
  white-space: pre-line;
  max-width: 36ch;
  overflow-wrap: break-word;
}
.fade-subtitle-enter-active,
.fade-subtitle-leave-active {
  transition: opacity 0.32s ease-in-out;
}
.fade-subtitle-enter-from,
.fade-subtitle-leave-to {
  opacity: 0;
}
.agent-tooltip-content.placement-bottom {
  margin-top: 0;
}
.agent-tooltip-content.placement-top {
  margin-bottom: 0;
}
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.18s cubic-bezier(0.4, 0, 0.2, 1);
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
.scale-enter-active,
.scale-leave-active {
  transition:
    opacity 0.18s cubic-bezier(0.4, 0, 0.2, 1),
    transform 0.18s cubic-bezier(0.4, 0, 0.2, 1);
}
.scale-enter-from,
.scale-leave-to {
  opacity: 0;
  transform: translate(-50%, -100%) scale(0.95);
}
.slide-enter-active,
.slide-leave-active {
  transition:
    opacity 0.18s cubic-bezier(0.4, 0, 0.2, 1),
    transform 0.18s cubic-bezier(0.4, 0, 0.2, 1);
}
.slide-enter-from,
.slide-leave-to {
  opacity: 0;
  transform: translate(-50%, -120%);
}
</style>
