<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import KanbanColumn from '../components/KanbanColumn.vue';
import KanbanItemModal from '../components/KanbanItemModal.vue';
import KanbanDragBar from '../components/KanbanDragBar.vue';
import KanbanAIGeneratorModal from '../components/KanbanAIGeneratorModal.vue';
import KanbanSendMessageModal from '../components/KanbanSendMessageModal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Spinner from 'shared/components/Spinner.vue';

const store = useStore();
const { t } = useI18n();

const showItemModal = ref(false);
const selectedItem = ref(null);
const selectedStage = ref(null);
const showDragBar = ref(false);
const draggedItem = ref(null);
const showAIGeneratorModal = ref(false);
const showActionsMenu = ref(false);
const showSendMessageModal = ref(false);
const selectedItemForMessage = ref(null);

const navigateToSettings = () => {
  window.router.push({ name: 'kanban_settings' });
};

const navigateToTemplates = () => {
  window.router.push({ name: 'kanban_templates' });
};

const toggleActionsMenu = () => {
  showActionsMenu.value = !showActionsMenu.value;
};

const handleManageFunnels = () => {
  navigateToSettings();
  showActionsMenu.value = false;
};

const handleKanbanSettings = () => {
  navigateToSettings();
  showActionsMenu.value = false;
};

const handleMessageTemplates = () => {
  navigateToTemplates();
  showActionsMenu.value = false;
};

const uiFlags = computed(() => store.getters['kanban/getUIFlags']);
const config = computed(() => store.getters['kanban/getConfig']);
const selectedFunnel = computed(
  () => store.getters['kanban/getSelectedFunnel']
);
const funnels = computed(() => store.getters['kanban/getFunnels']);
const filters = computed(() => store.getters['kanban/getFilters']);

const stages = computed(() => {
  if (!selectedFunnel.value) return [];
  return selectedFunnel.value.stages || [];
});

onMounted(async () => {
  try {
    // Load config first
    await store.dispatch('kanban/getConfig');

    // If config exists, load items
    if (config.value) {
      const funnelId = selectedFunnel.value?.id;
      if (funnelId) {
        await store.dispatch('kanban/get', { funnel_id: funnelId });
      }
    }
  } catch (error) {
    // Error already handled by store
  }
});

const openNewItemModal = (stage = null) => {
  selectedItem.value = null;
  selectedStage.value = stage;
  showItemModal.value = true;
};

const openEditItemModal = item => {
  selectedItem.value = item;
  selectedStage.value = null;
  showItemModal.value = true;
};

const closeItemModal = () => {
  showItemModal.value = false;
  selectedItem.value = null;
  selectedStage.value = null;
};

const handleItemSaved = async () => {
  closeItemModal();
  const funnelId = selectedFunnel.value?.id;
  if (funnelId) {
    await store.dispatch('kanban/get', { funnel_id: funnelId });
  }
};

const handleFunnelChange = async funnelId => {
  await store.dispatch('kanban/setSelectedFunnel', funnelId);
  if (funnelId) {
    await store.dispatch('kanban/get', { funnel_id: funnelId });
  }
};

const toggleWonFilter = () => {
  store.dispatch('kanban/toggleWonFilter');
};

const toggleLostFilter = () => {
  store.dispatch('kanban/toggleLostFilter');
};

const handleDragStart = item => {
  draggedItem.value = item;
  showDragBar.value = true;
};

const handleDragEnd = () => {
  showDragBar.value = false;
  draggedItem.value = null;
};

const handleMove = () => {
  // Default drag behavior - item will move to new column
  showDragBar.value = false;
};

const handleOpenChat = item => {
  if (item?.conversation_display_id) {
    const accountId = store.getters.getCurrentAccountId;
    const conversationId = item.conversation_display_id;
    const url = `/app/accounts/${accountId}/conversations/${conversationId}`;
    window.open(url, '_blank');
  }
  showDragBar.value = false;
};

const handleDuplicate = async item => {
  try {
    await store.dispatch('kanban/duplicate', item.id);
    useAlert(t('KANBAN.ITEM_DUPLICATED'));
    const funnelId = selectedFunnel.value?.id;
    if (funnelId) {
      await store.dispatch('kanban/get', { funnel_id: funnelId });
    }
  } catch (error) {
    // Error already handled by store
    useAlert(t('KANBAN.ERROR_DUPLICATING'), 'error');
  }
  showDragBar.value = false;
};

const openAIGeneratorModal = () => {
  showAIGeneratorModal.value = true;
};

const closeAIGeneratorModal = () => {
  showAIGeneratorModal.value = false;
};

const handleAIGenerated = async () => {
  closeAIGeneratorModal();
  const funnelId = selectedFunnel.value?.id;
  if (funnelId) {
    await store.dispatch('kanban/get', { funnel_id: funnelId });
  }
};

const openSendMessageModal = item => {
  selectedItemForMessage.value = item;
  showSendMessageModal.value = true;
};

const closeSendMessageModal = () => {
  showSendMessageModal.value = false;
  selectedItemForMessage.value = null;
};

const handleMessageSent = () => {
  closeSendMessageModal();
};

const handleQuickMessage = item => {
  openSendMessageModal(item);
};

const handleViewContact = item => {
  if (item?.conversation_display_id) {
    const accountId = store.getters.getCurrentAccountId;
    const conversationId = item.conversation_display_id;
    const url = `/app/accounts/${accountId}/conversations/${conversationId}`;
    window.open(url, '_blank');
  }
};
</script>

<template>
  <div class="flex h-full flex-col">
    <!-- Header -->
    <div
      class="flex items-center justify-between border-b border-slate-100 p-4 dark:border-slate-700"
    >
      <div class="flex items-center gap-4">
        <h1 class="text-2xl font-semibold text-slate-900 dark:text-slate-25">
          {{ t('KANBAN.TITLE') }}
        </h1>

        <!-- Kanban AI Badge -->
        <button
          class="flex items-center gap-2 rounded-lg bg-gradient-to-r from-purple-600 to-blue-600 px-3 py-1.5 text-sm font-medium text-white shadow-sm transition-all hover:shadow-md"
          @click="openAIGeneratorModal"
        >
          <i class="i-lucide-sparkles h-4 w-4" />
          <span>{{ t('KANBAN.AI.TITLE') }}</span>
        </button>

        <!-- Funnel Selector -->
        <select
          v-if="funnels.length > 0"
          :value="selectedFunnel?.id"
          class="rounded-md border border-slate-300 px-3 py-2 text-sm dark:border-slate-600 dark:bg-slate-800"
          @change="handleFunnelChange($event.target.value)"
        >
          <option v-for="funnel in funnels" :key="funnel.id" :value="funnel.id">
            {{ funnel.name }}
          </option>
        </select>
      </div>

      <div class="flex items-center gap-2">
        <!-- Filtro Ganhos -->
        <button
          class="rounded-md px-3 py-2 text-sm font-medium transition-colors"
          :class="[
            filters.showWon
              ? 'bg-green-600 text-white hover:bg-green-700'
              : 'bg-slate-200 text-slate-600 hover:bg-slate-300 dark:bg-slate-700 dark:text-slate-400 dark:hover:bg-slate-600',
          ]"
          :title="t('KANBAN.FILTER.WON')"
          @click="toggleWonFilter"
        >
          <i class="i-lucide-check-circle mr-1" />
          {{ t('KANBAN.FILTER.WON') }}
        </button>

        <!-- Filtro Perdidos -->
        <button
          class="rounded-md px-3 py-2 text-sm font-medium transition-colors"
          :class="[
            filters.showLost
              ? 'bg-red-600 text-white hover:bg-red-700'
              : 'bg-slate-200 text-slate-600 hover:bg-slate-300 dark:bg-slate-700 dark:text-slate-400 dark:hover:bg-slate-600',
          ]"
          :title="t('KANBAN.FILTER.LOST')"
          @click="toggleLostFilter"
        >
          <i class="i-lucide-x-circle mr-1" />
          {{ t('KANBAN.FILTER.LOST') }}
        </button>

        <div class="mx-2 h-6 w-px bg-slate-300 dark:bg-slate-600" />

        <Button variant="smooth" size="small" @click="navigateToTemplates">
          <i class="i-lucide-mail mr-1" />
          {{ t('KANBAN.QUICK_MESSAGE') }}
        </Button>
        <Button variant="smooth" size="small" @click="navigateToSettings">
          {{ t('KANBAN.SETTINGS') }}
        </Button>
        <Button variant="primary" size="small" @click="openNewItemModal()">
          {{ t('KANBAN.NEW_ITEM') }}
        </Button>

        <!-- Actions Menu Dropdown -->
        <div class="relative">
          <button
            class="flex h-8 w-8 items-center justify-center rounded-md text-slate-600 transition-colors hover:bg-slate-100 dark:text-slate-400 dark:hover:bg-slate-700"
            @click="toggleActionsMenu"
          >
            <i class="i-lucide-more-vertical h-5 w-5" />
          </button>

          <!-- Dropdown Menu -->
          <div
            v-if="showActionsMenu"
            class="absolute right-0 top-full z-50 mt-1 w-56 rounded-lg border border-slate-200 bg-white shadow-lg dark:border-slate-700 dark:bg-slate-800"
          >
            <div class="py-1">
              <button
                class="flex w-full items-center gap-3 px-4 py-2 text-left text-sm text-slate-700 transition-colors hover:bg-slate-50 dark:text-slate-300 dark:hover:bg-slate-700"
                @click="handleManageFunnels"
              >
                <i class="i-lucide-funnel h-4 w-4" />
                {{ t('KANBAN.MENU.MANAGE_FUNNELS') }}
              </button>

              <button
                class="flex w-full items-center gap-3 px-4 py-2 text-left text-sm text-slate-700 transition-colors hover:bg-slate-50 dark:text-slate-300 dark:hover:bg-slate-700"
                @click="handleKanbanSettings"
              >
                <i class="i-lucide-settings h-4 w-4" />
                {{ t('KANBAN.MENU.KANBAN_SETTINGS') }}
              </button>

              <button
                class="flex w-full items-center gap-3 px-4 py-2 text-left text-sm text-slate-700 transition-colors hover:bg-slate-50 dark:text-slate-300 dark:hover:bg-slate-700"
                @click="handleMessageTemplates"
              >
                <i class="i-lucide-mail h-4 w-4" />
                {{ t('KANBAN.MENU.MESSAGE_TEMPLATES') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Loading State -->
    <div
      v-if="uiFlags.isFetching && !config"
      class="flex h-full items-center justify-center"
    >
      <Spinner />
    </div>

    <!-- Empty State - No Config -->
    <EmptyState
      v-else-if="!config"
      :title="t('KANBAN.EMPTY_STATE.NO_CONFIG.TITLE')"
      :message="t('KANBAN.EMPTY_STATE.NO_CONFIG.MESSAGE')"
    >
      <Button variant="primary" size="small" @click="navigateToSettings">
        {{ t('KANBAN.EMPTY_STATE.NO_CONFIG.ACTION') }}
      </Button>
    </EmptyState>

    <!-- Empty State - No Funnels -->
    <EmptyState
      v-else-if="!funnels || funnels.length === 0"
      :title="t('KANBAN.EMPTY_STATE.NO_FUNNELS.TITLE')"
      :message="t('KANBAN.EMPTY_STATE.NO_FUNNELS.MESSAGE')"
    >
      <Button variant="primary" size="small" @click="navigateToSettings">
        {{ t('KANBAN.EMPTY_STATE.NO_FUNNELS.ACTION') }}
      </Button>
    </EmptyState>

    <!-- Kanban Board -->
    <div
      v-else
      class="flex h-full overflow-x-auto overflow-y-hidden bg-slate-50 p-4 dark:bg-slate-900"
    >
      <div class="flex gap-4">
        <KanbanColumn
          v-for="stage in stages"
          :key="stage"
          :stage="stage"
          :funnel-id="selectedFunnel.id"
          @new-item="openNewItemModal(stage)"
          @edit-item="openEditItemModal"
          @drag-start="handleDragStart"
          @drag-end="handleDragEnd"
          @quick-message="handleQuickMessage"
          @view-contact="handleViewContact"
        />
      </div>
    </div>

    <!-- Drag Bar -->
    <KanbanDragBar
      :visible="showDragBar"
      :item="draggedItem"
      @move="handleMove"
      @open-chat="handleOpenChat"
      @duplicate="handleDuplicate"
    />

    <!-- Item Modal -->
    <KanbanItemModal
      v-if="showItemModal"
      :item="selectedItem"
      :initial-stage="selectedStage"
      :funnel-id="selectedFunnel?.id"
      @close="closeItemModal"
      @saved="handleItemSaved"
    />

    <!-- AI Generator Modal -->
    <KanbanAIGeneratorModal
      v-if="showAIGeneratorModal"
      :funnel-id="selectedFunnel?.id"
      @close="closeAIGeneratorModal"
      @generated="handleAIGenerated"
    />

    <!-- Send Message Modal -->
    <KanbanSendMessageModal
      v-if="showSendMessageModal && selectedItemForMessage"
      :item="selectedItemForMessage"
      :funnel-id="selectedFunnel?.id"
      @close="closeSendMessageModal"
      @sent="handleMessageSent"
    />
  </div>
</template>
