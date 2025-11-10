<script setup>
import { ref, onMounted, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import KanbanAPI from '../../../../api/kanban';
import FunnelAPI from '../../../../api/funnel';
import KanbanItemDetails from './KanbanItemDetails.vue';
import KanbanItemForm from './KanbanItemForm.vue';
import { useStore } from 'vuex';
import { emitter } from 'shared/helpers/mitt';

const props = defineProps({
  itemId: {
    type: [Number, String],
    required: true,
  },
  forceReload: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['back', 'itemUpdated', 'quick-action']);
const { t } = useI18n();
const router = useRouter();
const store = useStore();

const item = ref(null);
const isLoading = ref(true);
const isEditing = ref(false);
const forceReloadCounter = ref(0);

// Modal de mover funil
const showMoveFunnelModal = ref(false);
const availableFunnels = ref([]);
const selectedFunnelId = ref(null);
const selectedStage = ref(null);
const isMovingItem = ref(false);

const statusInfo = computed(() => {
  if (!item.value || !item.value.item_details?.status) {
    return null;
  }
  const status = item.value.item_details.status;
  if (status === 'won') {
    const closedOffer = item.value.item_details.closed_offer;
    let label = t('KANBAN.BULK_ACTIONS.ITEM_STATUS.WON');

    if (closedOffer) {
      const currency = closedOffer.currency || item.value.item_details.currency;
      const value = closedOffer.value;
      const symbol = currency?.symbol || 'R$';
      const formattedValue = new Intl.NumberFormat('pt-BR', {
        style: 'currency',
        currency: currency?.code || 'BRL'
      }).format(value);

      label = `${label} - Oferta fechada: ${formattedValue}`;
    }

    return {
      label,
      class: 'bg-green-50 text-green-700 dark:bg-green-900 dark:text-green-300',
      icon: 'checkmark-circle',
    };
  }
  if (status === 'lost') {
    return {
      label: t('KANBAN.BULK_ACTIONS.ITEM_STATUS.LOST'),
      class: 'bg-red-50 text-red-700 dark:bg-red-900 dark:text-red-300',
      icon: 'dismiss-circle',
    };
  }
  return null;
});

const priorityInfo = computed(() => {
  if (!item.value || !item.value.item_details?.priority) {
    return null;
  }
  const priority = item.value.item_details.priority.toLowerCase();
  if (priority === 'none') return null;

  const priorityMap = {
    urgent: {
      label: t('KANBAN.PRIORITY_LABELS.URGENT') || 'Urgente',
      class: 'bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200',
    },
    high: {
      label: t('KANBAN.PRIORITY_LABELS.HIGH'),
      class: 'bg-n-ruby-3 dark:bg-n-ruby-8 text-n-ruby-9 dark:text-n-ruby-1',
    },
    medium: {
      label: t('KANBAN.PRIORITY_LABELS.MEDIUM'),
      class: 'bg-yellow-50 dark:bg-yellow-800 text-yellow-800 dark:text-yellow-50',
    },
    low: {
      label: t('KANBAN.PRIORITY_LABELS.LOW'),
      class: 'bg-green-50 dark:bg-green-800 text-green-800 dark:text-green-50',
    },
  };

  return priorityMap[priority] || null;
});

// Computed para informações do status do item
const itemStatusInfo = computed(() => {
  const status = item.value?.item_details?.status?.toLowerCase();

  const statusMap = {
    won: {
      label: t('KANBAN.BULK_ACTIONS.ITEM_STATUS.WON'),
      class: 'bg-green-50 dark:bg-green-900 text-green-700 dark:text-green-300',
    },
    lost: {
      label: t('KANBAN.BULK_ACTIONS.ITEM_STATUS.LOST'),
      class: 'bg-red-50 dark:bg-red-900 text-red-700 dark:text-red-300',
    },
  };

  // Se não há status definido, retorna "Aberto" com cor neutra
  if (!status) {
    return {
      label: 'Aberto',
      class: 'bg-blue-50 dark:bg-blue-900 text-blue-700 dark:text-blue-300',
    };
  }

  return statusMap[status] || {
    label: 'Aberto',
    class: 'bg-blue-50 dark:bg-blue-900 text-blue-700 dark:text-blue-300',
  };
});

// Computed para custom_attributes da conversa
const conversationCustomAttributes = computed(() => {
  const conversation = item.value?.conversation;
  if (!conversation?.custom_attributes) return {};

  // Filtrar apenas atributos não vazios
  const filtered = {};
  Object.entries(conversation.custom_attributes).forEach(([key, value]) => {
    if (value !== null && value !== undefined && value !== '') {
      filtered[key] = value;
    }
  });

  return filtered;
});

// Computed para formatted updated_at
const formattedUpdatedAt = computed(() => {
  if (!item.value?.updated_at) return '';
  try {
    const date = new Date(item.value.updated_at);
    return date.toLocaleString('pt-BR', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch (error) {
    return '';
  }
});

// Computed para formatted deadline_at
const formattedDeadlineAt = computed(() => {
  if (!item.value?.item_details?.deadline_at) return '';
  try {
    const date = new Date(item.value.item_details.deadline_at);
    return date.toLocaleDateString('pt-BR', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
  } catch (error) {
    return '';
  }
});

// Funções para modal de mover funil
const openMoveFunnelModal = async () => {
  try {
    // Buscar todos os funis disponíveis
    const { data } = await FunnelAPI.get();

    // Filtrar para não incluir o funil atual do item
    availableFunnels.value = data.filter(funnel => funnel.id !== item.value?.funnel_id);

    // Não pré-selecionar nenhum funil, deixar o usuário escolher
    selectedFunnelId.value = null;
    selectedStage.value = null;

    showMoveFunnelModal.value = true;

    // Mostrar toast informativo
    emitter.emit('newToastMessage', {
      message: 'Selecione o funil e etapa para mover o item',
      type: 'info',
    });
  } catch (error) {
    console.error('Erro ao carregar funis:', error);

    // Mostrar toast de erro se houver problema ao carregar funis
    emitter.emit('newToastMessage', {
      message: 'Erro ao carregar funis disponíveis',
      type: 'error',
    });
  }
};

const closeMoveFunnelModal = () => {
  showMoveFunnelModal.value = false;
  selectedFunnelId.value = null;
  selectedStage.value = null;
};

const moveItemToFunnel = async () => {
  if (!selectedFunnelId.value || !item.value) return;

  try {
    isMovingItem.value = true;

    // Mover o item para o novo funil/etapa
    await KanbanAPI.moveToFunnel(
      item.value.id,
      selectedFunnelId.value,
      selectedStage.value
    );

    // Atualizar o funil selecionado no store se necessário
    if (selectedFunnelId.value !== item.value.funnel_id) {
      const newFunnel = availableFunnels.value.find(f => f.id === selectedFunnelId.value);
      if (newFunnel) {
        await store.dispatch('funnel/setSelectedFunnel', newFunnel);
      }
    }

    // Recarregar os dados do item
    await fetchItemDetails();

    // Emitir evento de atualização
    emit('itemUpdated');

    // Fechar modal
    closeMoveFunnelModal();

    // Mostrar toast de sucesso
    emitter.emit('newToastMessage', {
      message: 'Item movido para o novo funil com sucesso',
      type: 'success',
    });
  } catch (error) {
    console.error('Erro ao mover item:', error);

    // Mostrar toast de erro
    emitter.emit('newToastMessage', {
      message: 'Erro ao mover item para o novo funil',
      type: 'error',
    });
  } finally {
    isMovingItem.value = false;
  }
};

// Computed para o funil selecionado no modal
const selectedFunnelForModal = computed(() => {
  return availableFunnels.value.find(f => f.id === selectedFunnelId.value);
});

// Mover fetchItemDetails para antes do watch
const fetchItemDetails = async () => {
  try {
    isLoading.value = true;
    const { data } = await KanbanAPI.getItem(props.itemId);

    // Atualizar com os novos dados
    item.value = data;

    // Verificar se o funil do item está definido como selecionado
    // Isso é importante quando o item é acessado diretamente pela URL
    if (item.value && item.value.funnel_id) {
      const currentSelectedFunnel = store.getters['funnel/getSelectedFunnel'];
      if (!currentSelectedFunnel || currentSelectedFunnel.id !== item.value.funnel_id) {
        // Garantir que os funis estão carregados primeiro
        await store.dispatch('funnel/fetch');
        
        // Buscar o funil pelos funis disponíveis no store
        const funnels = store.getters['funnel/getFunnels'];
        const itemFunnel = funnels.find(f => f.id === item.value.funnel_id);
        if (itemFunnel) {
          // Definir o funil do item como selecionado
          await store.dispatch('funnel/setSelectedFunnel', itemFunnel);
        }
      }
    }
  } catch (error) {
    // Handle error silently
  } finally {
    isLoading.value = false;
  }
};

// Watch após a definição da função
watch(
  [() => props.itemId, () => props.forceReload],
  () => {
    // Limpar estado atual antes de buscar novo item
    item.value = null;
    isEditing.value = false;
    fetchItemDetails();
  },
  { immediate: true }
);

const handleBack = () => {
  // Limpar estados
  item.value = null;
  isEditing.value = false;

  // Remover o parâmetro 'item' da URL
  const currentQuery = { ...router.currentRoute.value.query };
  delete currentQuery.item;
  router.replace({ query: currentQuery });

  emit('back');
};

const handleEdit = async () => {
  // Recarregar os dados do item para garantir que temos as notas mais recentes
  await fetchItemDetails();
  isEditing.value = true;
};

const handleClose = () => {
  isEditing.value = false;
};

const handleItemUpdated = async () => {
  // Recarregar os dados do item para refletir as mudanças (como novas notas)
  await fetchItemDetails();
  emit('itemUpdated');
  isEditing.value = false; // Voltar para modo de visualização após edição
};

const handleDetailsDeleted = () => {
  // Remover o parâmetro 'item' da URL quando o item for deletado
  const currentQuery = { ...router.currentRoute.value.query };
  delete currentQuery.item;
  router.replace({ query: currentQuery });

  emit('itemUpdated');
  emit('back');
};

const handleQuickAction = (actionId) => {
  // Emitir evento para o componente pai lidar com a ação
  emit('quick-action', actionId);
};

const selectedFunnel = computed(() => {
  // First try to get from store
  const storeFunnel = store.getters['funnel/getSelectedFunnel'];
  if (storeFunnel) return storeFunnel;
  
  // If no funnel in store but we have item data, try to find the funnel by item's funnel_id
  if (item.value?.funnel_id) {
    const funnels = store.getters['funnel/getFunnels'];
    return funnels.find(f => f.id === item.value.funnel_id) || null;
  }
  
  return null;
});
</script>

<template>
  <div
    class="flex flex-col h-full w-full bg-white dark:bg-slate-900 overflow-hidden"
  >
    <!-- Header -->
    <div
      class="border-b border-slate-200 dark:border-slate-700 px-4 py-3 flex items-center justify-between"
    >
      <div class="flex items-center gap-2">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-chevron-left-icon lucide-chevron-left cursor-pointer text-slate-600 dark:text-slate-400" @click="handleBack">
          <path d="m15 18-6-6 6-6"/>
        </svg>
        <div class="flex items-center gap-3">
          <h2 class="text-base font-medium">
            {{
              isLoading
                ? 'Carregando...'
                : item?.item_details?.title || t('ITEM_DETAILS')
            }}
          </h2>
          <!-- Status do Item -->
          <span
            v-if="!isLoading"
            class="px-2.5 py-1 text-xs font-medium rounded-full"
            :class="itemStatusInfo.class"
          >
            {{ itemStatusInfo.label }}
          </span>
          <span
            v-if="!isLoading && priorityInfo"
            class="px-2.5 py-1 text-xs font-medium rounded-full"
            :class="priorityInfo.class"
          >
            {{ priorityInfo.label }}
          </span>
          <!-- Custom Attributes da Conversa -->
          <div
            v-if="!isLoading && Object.keys(conversationCustomAttributes).length > 0"
            class="flex items-center gap-2"
          >
            <span
              v-for="(value, key) in conversationCustomAttributes"
              :key="key"
              class="px-1.5 py-0.5 text-[10px] font-medium bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300 rounded-full"
              :title="`${key}: ${value}`"
            >
              {{ key }}: {{ value }}
            </span>
          </div>
          <!-- Updated At -->
          <div
            v-if="!isLoading && formattedUpdatedAt"
            class="text-[10px] text-slate-500 dark:text-slate-400 ml-2 hidden md:block"
          >
            {{ t('KANBAN.UPDATED_AT') || 'Atualizado em' }}: {{ formattedUpdatedAt }}
          </div>
        </div>
      </div>

      <div v-if="!isEditing && !isLoading" class="flex items-center gap-3">
        <!-- Data limite -->
        <div
          v-if="formattedDeadlineAt"
          class="flex items-center gap-1.5 px-3 py-1.5"
          :style="{ backgroundColor: '#fef3c7', borderColor: '#d97706' }"
          style="border-width: 1px; border-radius: 8px; box-shadow: 0 1px 2px 0 rgb(0 0 0 / 0.05); transition: all 200ms;"
        >
          <fluent-icon
            icon="calendar-clock"
            size="14"
            :style="{ color: '#d97706' }"
            class="drop-shadow-sm"
          />
          <span class="text-xs font-medium tracking-wide" :style="{ color: '#d97706' }">
            {{ t('KANBAN.DEADLINE') || 'Prazo' }}: {{ formattedDeadlineAt }}
          </span>
        </div>

        <!-- Botão de mover funil -->
        <button
          class="p-1.5 rounded-md"
          :style="{ backgroundColor: '#3b82f6', color: 'white', borderColor: '#2563eb' }"
          style="border-width: 1px; border-radius: 6px; box-shadow: 0 1px 2px 0 rgb(0 0 0 / 0.05); transition: all 200ms;"
          @mouseover="($event.target.style.backgroundColor = '#2563eb')"
          @mouseleave="($event.target.style.backgroundColor = '#3b82f6')"
          @click="openMoveFunnelModal"
        >
          <span class="flex items-center gap-1">
            <fluent-icon icon="arrow-right" size="14" />
            <span class="text-xs">{{ t('KANBAN.MOVE_TO_FUNNEL') || 'Mover Funil' }}</span>
          </span>
        </button>

        <!-- Botão de editar -->
        <button
          class="p-1.5 rounded-md bg-slate-100 dark:bg-slate-800 hover:bg-slate-200 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-300"
          @click="handleEdit"
        >
          <span class="flex items-center gap-1">
            <fluent-icon icon="edit" size="14" />
            <span class="text-xs">{{ t('KANBAN.FORM.EDIT_ITEM') }}</span>
          </span>
        </button>
      </div>
    </div>

    <!-- Status Header -->
    <div
      v-if="statusInfo && !isLoading"
      :class="[
        'px-4 py-1.5 flex items-center gap-2 text-xs font-medium',
        statusInfo.class,
      ]"
    >
      <fluent-icon :icon="statusInfo.icon" size="14" />
      <span>{{ statusInfo.label }}</span>
      <span v-if="item.item_details.reason" class="text-[10px] italic">
        - {{ item.item_details.reason }}
      </span>
    </div>

    <!-- Loading State -->
    <div v-if="isLoading" class="flex-1 flex justify-center items-center py-12">
      <span
        class="w-8 h-8 border-2 border-t-woot-500 border-r-woot-500 border-b-transparent border-l-transparent rounded-full animate-spin"
      />
    </div>

    <!-- Content -->
    <div v-else class="flex-1 overflow-auto">
      <!-- Modo de visualização -->
      <KanbanItemDetails
        v-if="!isEditing && item"
        :item-id="item.id"
        :force-reload="forceReloadCounter"
        @close="handleBack"
        @edit="handleEdit"
        @item-updated="handleItemUpdated"
        @deleted="handleDetailsDeleted"
      />

      <!-- Modo de edição -->
      <KanbanItemForm
        v-if="isEditing && item && (selectedFunnel || item.funnel_id)"
        :funnel-id="selectedFunnel?.id || item.funnel_id"
        :stage="item.funnel_stage"
        :position="item.position"
        :initial-data="item"
        is-editing
        @saved="handleItemUpdated"
        @close="handleClose"
      />
    </div>

    <!-- Modal de mover funil -->
    <div
      v-if="showMoveFunnelModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50"
      @click="closeMoveFunnelModal"
    >
      <div
        class="bg-white dark:bg-slate-800 rounded-lg shadow-xl max-w-lg w-full mx-4 max-h-[90vh] overflow-hidden"
        @click.stop
      >
        <!-- Header do modal -->
        <div class="flex items-center justify-between p-6 border-b border-slate-200 dark:border-slate-700">
          <div class="flex items-center gap-3">
            <div
              class="flex items-center justify-center w-8 h-8 rounded-lg bg-woot-50 dark:bg-woot-900/20"
            >
              <fluent-icon icon="arrow-right" size="18" class="text-woot-500" />
            </div>
            <h3 class="text-lg font-semibold text-slate-900 dark:text-slate-100">
              {{ t('KANBAN.MOVE_TO_FUNNEL') || 'Mover para Funil' }}
            </h3>
          </div>
          <button
            @click="closeMoveFunnelModal"
            class="text-slate-400 hover:text-slate-600 dark:text-slate-500 dark:hover:text-slate-300"
          >
            <fluent-icon icon="dismiss" size="20" />
          </button>
        </div>

        <!-- Corpo do modal -->
        <div class="p-6 space-y-6 overflow-y-auto max-h-[calc(90vh-140px)]">
          <!-- Seleção de funil -->
          <div class="space-y-2">
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300">
              {{ t('KANBAN.FUNNEL') || 'Funil' }}
            </label>
            <select
              v-model="selectedFunnelId"
              class="w-full px-3 py-2.5 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
            >
              <option value="">{{ t('KANBAN.SELECT_FUNNEL') || 'Selecionar funil...' }}</option>
              <option
                v-for="funnel in availableFunnels"
                :key="funnel.id"
                :value="funnel.id"
              >
                {{ funnel.name }}
              </option>
            </select>
          </div>

          <!-- Seleção de etapa -->
          <div v-if="selectedFunnelForModal" class="space-y-2">
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300">
              {{ t('KANBAN.STAGE') || 'Etapa' }}
            </label>
            <select
              v-model="selectedStage"
              class="w-full px-3 py-2.5 text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500"
            >
              <option value="">{{ t('KANBAN.SELECT_STAGE') || 'Selecionar etapa...' }}</option>
              <option
                v-for="[stageId, stage] in Object.entries(selectedFunnelForModal.stages)"
                :key="stageId"
                :value="stageId"
              >
                {{ stage.name }}
              </option>
            </select>
          </div>
        </div>

        <!-- Footer do modal -->
        <div class="flex justify-end space-x-2 pt-4 p-6 border-t border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800/50">
          <button
            type="button"
            @click="closeMoveFunnelModal"
            class="px-4 py-2 text-sm font-medium text-slate-700 dark:text-slate-300 bg-white dark:bg-slate-700 hover:bg-slate-50 dark:hover:bg-slate-600 border border-slate-200 dark:border-slate-600 rounded-lg transition-colors"
          >
            {{ t('KANBAN.CANCEL') || 'Cancelar' }}
          </button>
          <button
            type="button"
            @click="moveItemToFunnel"
            :disabled="!selectedFunnelId || isMovingItem"
            class="px-4 py-2 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 disabled:bg-woot-400 disabled:cursor-not-allowed rounded-lg flex items-center gap-2 transition-colors"
          >
            <span v-if="isMovingItem" class="loading-spinner"></span>
            <fluent-icon v-else icon="arrow-right" size="14" />
            {{ isMovingItem ? (t('KANBAN.MOVING') || 'Movendo...') : (t('KANBAN.MOVE') || 'Mover') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
/* Estilos para animação de carregamento */
@keyframes spin {
  from {
    transform: rotate(0deg);
  }
  to {
    transform: rotate(360deg);
  }
}

.animate-spin {
  animation: spin 1s linear infinite;
}

.loading-spinner {
  @apply w-4 h-4 border-2 border-slate-200 border-t-woot-500 rounded-full animate-spin;
}
</style>
