<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import draggable from 'vuedraggable';
import KanbanCard from './KanbanCard.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  stage: {
    type: String,
    required: true,
  },
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits([
  'newItem',
  'editItem',
  'dragStart',
  'dragEnd',
  'quickMessage',
  'viewContact',
]);

const store = useStore();

const items = computed({
  get: () =>
    store.getters['kanban/getItemsByStage'](props.funnelId, props.stage),
  set: value => {
    // Update order
    const itemIds = value.map(item => item.id);
    store.dispatch('kanban/reorder', {
      funnelId: props.funnelId,
      funnelStage: props.stage,
      itemIds,
    });
  },
});

const itemCount = computed(() => items.value.length);

const handleDragStart = event => {
  // eslint-disable-next-line no-underscore-dangle
  const item = event.item._underlying_vm_;
  emit('dragStart', item);
};

const handleDragEnd = async event => {
  emit('dragEnd');

  if (event.added) {
    // Item moved to this column from another
    const item = event.added.element;
    const newPosition = event.added.newIndex;

    try {
      await store.dispatch('kanban/move', {
        id: item.id,
        funnel_stage: props.stage,
        position: newPosition,
      });
    } catch (error) {
      // Error already handled by store
    }
  }
};

const handleNewItem = () => {
  emit('newItem', props.stage);
};

const handleEditItem = item => {
  emit('editItem', item);
};

const handleQuickMessage = item => {
  emit('quickMessage', item);
};

const handleViewContact = item => {
  emit('viewContact', item);
};
</script>

<template>
  <div
    class="flex w-80 flex-shrink-0 flex-col rounded-lg bg-white shadow-sm dark:bg-slate-800"
  >
    <!-- Column Header -->
    <div
      class="flex items-center justify-between border-b border-slate-200 p-4 dark:border-slate-700"
    >
      <div class="flex items-center gap-2">
        <h3 class="font-semibold text-slate-900 dark:text-slate-25">
          {{ stage }}
        </h3>
        <span
          class="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-600 dark:bg-slate-700 dark:text-slate-300"
        >
          {{ itemCount }}
        </span>
      </div>
      <Button variant="clear" size="small" icon="add" @click="handleNewItem" />
    </div>

    <!-- Cards Container -->
    <draggable
      v-model="items"
      group="kanban-items"
      item-key="id"
      class="flex min-h-[200px] flex-1 flex-col gap-3 overflow-y-auto p-4"
      @start="handleDragStart"
      @end="handleDragEnd"
    >
      <template #item="{ element }">
        <KanbanCard
          :item="element"
          @click="handleEditItem(element)"
          @quick-message="handleQuickMessage"
          @view-contact="handleViewContact"
        />
      </template>
    </draggable>
  </div>
</template>
