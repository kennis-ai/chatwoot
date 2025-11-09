<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Modal from '../../../../components/Modal.vue';
import Button from '../../../../components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();
const isDropdownOpen = ref(false);
const showModal = ref(false);
const isMobile = ref(window.innerWidth < 768);

const funnels = computed(() =>
  store.getters['funnel/getFunnels'].filter(funnel => funnel.active)
);
const selectedFunnel = computed(
  () => store.getters['funnel/getSelectedFunnel']
);
const uiFlags = computed(() => store.getters['funnel/getUIFlags']);
const stageStats = computed(() => store.getters['funnel/getStageStats']);

// Computed para o estilo do badge de count
const funnelCountStyle = computed(() => ({
  backgroundColor: '#60A5FA', // Azul claro
  color: '#FFFFFF',
}));

// Função para escurecer a cor
const darkenColor = color => {
  const hex = color.replace('#', '');
  const r = parseInt(hex.substring(0, 2), 16);
  const g = parseInt(hex.substring(2, 4), 16);
  const b = parseInt(hex.substring(4, 6), 16);

  const darkenAmount = 0.85;
  const dr = Math.floor(r * darkenAmount);
  const dg = Math.floor(g * darkenAmount);
  const db = Math.floor(b * darkenAmount);

  return `#${dr.toString(16).padStart(2, '0')}${dg
    .toString(16)
    .padStart(2, '0')}${db.toString(16).padStart(2, '0')}`;
};

const toggleDropdown = () => {
  if (isMobile.value) {
    showModal.value = true;
  } else {
    isDropdownOpen.value = !isDropdownOpen.value;
  }
};

const selectFunnel = async funnel => {
  try {
    await store.dispatch('funnel/setSelectedFunnel', funnel);

    // Busca os stats das etapas do funil selecionado
    if (funnel && funnel.id) {
      await store.dispatch('funnel/fetchStageStats', {
        funnelId: funnel.id,
        filterParams: {},
      });
    }

    isDropdownOpen.value = false;
    showModal.value = false;
  } catch (error) {
    // Notifica o usuário sobre o erro
    store.dispatch('notifications/show', {
      type: 'error',
      message: t('KANBAN.ERRORS.FUNNEL_SELECTION_FAILED'),
    });
  }
};

// Atualiza o estado mobile quando a janela é redimensionada
const handleResize = () => {
  isMobile.value = window.innerWidth < 768;
};

const closeDropdown = event => {
  const target = event.target;
  const isDropdownClick = target.closest('.funnel-selector');

  if (!isDropdownClick) {
    isDropdownOpen.value = false;
  }
};

const getFunnelTotalCount = funnel => {
  if (!funnel || !funnel.id) return 0;

  const stats = stageStats.value(funnel.id);
  if (!stats || Object.keys(stats).length === 0) return 0;

  // Soma todos os counts das etapas
  return Object.values(stats).reduce((total, stage) => {
    return total + (stage.count || 0);
  }, 0);
};

onMounted(async () => {
  try {
    await store.dispatch('funnel/fetch');

    // Se não houver funil selecionado e existirem funis, seleciona o primeiro
    if (!selectedFunnel.value && funnels.value.length > 0) {
      await selectFunnel(funnels.value[0]);
    } else if (selectedFunnel.value) {
      // Se já há um funil selecionado, busca os stats dele
      await store.dispatch('funnel/fetchStageStats', {
        funnelId: selectedFunnel.value.id,
        filterParams: {},
      });
    }

    window.addEventListener('resize', handleResize);
    document.addEventListener('click', closeDropdown);
  } catch (error) {
    // Notifica o usuário sobre o erro
    store.dispatch('notifications/show', {
      type: 'error',
      message: t('KANBAN.ERRORS.FUNNEL_FETCH_FAILED'),
    });
  }
});

// Watch para garantir que um funil seja selecionado quando os funis são carregados
watch(
  funnels,
  async newFunnels => {
    if (newFunnels.length > 0 && !selectedFunnel.value) {
      console.log(
        '[FUNNEL-SELECTOR] Selecionando primeiro funil automaticamente'
      );
      await selectFunnel(newFunnels[0]);
    }
  },
  { immediate: true }
);

// Watch para buscar stats quando o funil selecionado muda
watch(selectedFunnel, async (newFunnel, oldFunnel) => {
  // Só busca stats se o funil mudou e não é o mesmo
  if (
    newFunnel &&
    newFunnel.id &&
    (!oldFunnel || oldFunnel.id !== newFunnel.id)
  ) {
    try {
      await store.dispatch('funnel/fetchStageStats', {
        funnelId: newFunnel.id,
        filterParams: {},
      });
    } catch (error) {
      console.error('Erro ao buscar stats do funil:', error);
    }
  }
});

onUnmounted(() => {
  window.removeEventListener('resize', handleResize);
  document.removeEventListener('click', closeDropdown);
});
</script>

<template>
  <div class="funnel-selector">
    <Button
      type="button"
      variant="outline"
      color="slate"
      size="sm"
      :is-loading="uiFlags.isFetching"
      @click="toggleDropdown"
    >
      <!-- Ícone removido conforme solicitado -->
      <!-- <template #icon>
        <fluent-icon icon="task" size="16" />
      </template> -->
      <template v-if="uiFlags.isFetching">
        <span class="md:inline hidden">{{ $t('KANBAN.LOADING_FUNNELS') }}</span>
      </template>
      <template v-else>
        <span class="md:inline hidden flex items-center justify-between w-full">
          <span class="text-[12px]">{{
            selectedFunnel ? selectedFunnel.name : $t('KANBAN.SELECT_FUNNEL')
          }}</span>
          <span
            v-if="selectedFunnel && getFunnelTotalCount(selectedFunnel) > 0"
            :key="`funnel-count-${selectedFunnel.id}-${getFunnelTotalCount(selectedFunnel)}`"
            class="inline-flex items-center justify-center min-w-[18px] h-4 px-1 text-xs font-medium rounded ml-2"
            :style="funnelCountStyle"
          >
            {{ getFunnelTotalCount(selectedFunnel) }}
          </span>
        </span>
      </template>
      <fluent-icon
        icon="chevron-down"
        size="16"
        class="md:inline hidden ml-1"
      />
    </Button>

    <!-- Dropdown para desktop -->
    <div v-if="isDropdownOpen && !isMobile" class="dropdown-menu">
      <div
        v-for="funnel in funnels"
        :key="funnel.id"
        class="dropdown-item"
        :class="{ active: selectedFunnel?.id === funnel.id }"
        @click="selectFunnel(funnel)"
      >
        <span class="flex items-center justify-between w-full">
          <span class="text-[12px]">{{ funnel.name }}</span>
          <span
            v-if="getFunnelTotalCount(funnel) > 0"
            :key="`dropdown-count-${funnel.id}-${getFunnelTotalCount(funnel)}`"
            class="inline-flex items-center justify-center min-w-[18px] h-4 px-1 text-xs font-medium rounded ml-2"
            :style="{
              backgroundColor: '#60A5FA',
              color: '#FFFFFF',
            }"
          >
            {{ getFunnelTotalCount(funnel) }}
          </span>
        </span>
      </div>
    </div>

    <!-- Modal para mobile -->
    <Modal
      v-model:show="showModal"
      :on-close="() => (showModal = false)"
      size="small"
    >
      <div class="p-4">
        <h3 class="text-lg font-medium mb-3">Selecionar Funil</h3>
        <div class="funnel-list">
          <button
            v-for="funnel in funnels"
            :key="funnel.id"
            class="funnel-option"
            :class="{ 'funnel-active': selectedFunnel?.id === funnel.id }"
            @click="selectFunnel(funnel)"
          >
            <!-- Ícone removido conforme solicitado -->
            <!-- <fluent-icon icon="task" size="18" class="mr-2" /> -->
            <div class="funnel-name flex items-center justify-between w-full">
              <span class="text-[12px]">{{ funnel.name }}</span>
              <span
                v-if="getFunnelTotalCount(funnel) > 0"
                :key="`modal-count-${funnel.id}-${getFunnelTotalCount(funnel)}`"
                class="inline-flex items-center justify-center min-w-[18px] h-4 px-1 text-xs font-medium rounded ml-2"
                :style="{
                  backgroundColor: '#60A5FA',
                  color: '#FFFFFF',
                }"
              >
                {{ getFunnelTotalCount(funnel) }}
              </span>
            </div>
            <fluent-icon
              v-if="selectedFunnel?.id === funnel.id"
              icon="checkmark"
              size="16"
              class="ml-auto text-woot-500"
            />
          </button>
        </div>
      </div>
    </Modal>
  </div>
</template>

<style lang="scss" scoped>
.funnel-selector {
  position: relative;
  display: inline-block;
}

.dropdown-menu {
  position: absolute;
  top: 100%;
  left: 0;
  z-index: 9995;
  min-width: 200px;
  margin-top: 0.25rem;
  padding: 0.25rem 0;
  background: white;
  border: 1px solid #e2e8f0;
  border-radius: 0.5rem;
  box-shadow: 0 4px 24px 0 rgba(30, 41, 59, 0.08);

  @apply dark:bg-slate-800 dark:border-slate-700;
}

.dropdown-item {
  padding: 0.5rem 1rem;
  cursor: pointer;
  border-radius: 0.375rem;
  color: #374151;
  @apply dark:text-slate-100;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;

  &:hover {
    background: #f9fafb;
    @apply dark:bg-slate-700;
  }

  &.active {
    background: #f9fafb;
    color: #6366f1;

    @apply dark:bg-slate-700 dark:text-woot-500;
  }
}

// Estilos para as opções no modal móvel
.funnel-list {
  @apply flex flex-col gap-2 max-h-[50vh] overflow-y-auto;
}

.funnel-option {
  @apply flex items-center p-3 rounded-lg text-left w-full;
  @apply text-slate-700 dark:text-slate-200;
  @apply hover:bg-slate-50 dark:hover:bg-slate-700;
  @apply transition-colors duration-150;

  .funnel-name {
    @apply font-medium;
    word-break: break-word;
  }

  &.funnel-active {
    @apply bg-woot-50 text-woot-600 dark:bg-woot-900/20 dark:text-woot-300;
  }
}
</style>
