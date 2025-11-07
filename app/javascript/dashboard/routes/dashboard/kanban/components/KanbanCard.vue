<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['quickMessage', 'viewContact']);

const { t } = useI18n();

const showContextMenu = ref(false);

const title = computed(() => props.item.item_details?.title || 'Untitled');
const description = computed(() => props.item.item_details?.description || '');
const priority = computed(() => props.item.item_details?.priority || 'medium');
const status = computed(() => props.item.item_details?.status || 'open');
const assignedAgents = computed(() => props.item.assigned_agents || []);
const labels = computed(() => props.item.item_details?.labels || []);
const conversationId = computed(() => props.item.conversation_display_id);

const statusConfig = computed(() => {
  const configs = {
    won: {
      color:
        'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
      icon: 'i-lucide-check-circle',
      label: t('KANBAN.STATUS.WON'),
    },
    lost: {
      color: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
      icon: 'i-lucide-x-circle',
      label: t('KANBAN.STATUS.LOST'),
    },
  };
  return configs[status.value];
});

const priorityColor = computed(() => {
  const colors = {
    low: 'bg-slate-100 text-slate-700 dark:bg-slate-700 dark:text-slate-300',
    medium:
      'bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300',
    high: 'bg-orange-100 text-orange-700 dark:bg-orange-900 dark:text-orange-300',
    urgent: 'bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300',
  };
  return colors[priority.value] || colors.medium;
});

const truncateText = (text, maxLength = 100) => {
  if (!text || text.length <= maxLength) return text;
  return text.substring(0, maxLength) + '...';
};

const toggleContextMenu = () => {
  showContextMenu.value = !showContextMenu.value;
};

const handleQuickMessage = () => {
  emit('quickMessage', props.item);
  showContextMenu.value = false;
};

const handleViewContact = () => {
  emit('viewContact', props.item);
  showContextMenu.value = false;
};
</script>

<template>
  <div
    class="group relative cursor-pointer rounded-lg border border-slate-200 bg-white p-3 shadow-sm transition-all hover:shadow-md dark:border-slate-700 dark:bg-slate-800"
  >
    <!-- Context Menu Button -->
    <div class="absolute right-2 top-2">
      <button
        class="flex h-6 w-6 items-center justify-center rounded opacity-0 transition-opacity hover:bg-slate-100 group-hover:opacity-100 dark:hover:bg-slate-700"
        @click.stop="toggleContextMenu"
      >
        <i
          class="i-lucide-more-vertical h-4 w-4 text-slate-600 dark:text-slate-400"
        />
      </button>

      <!-- Dropdown Menu -->
      <div
        v-if="showContextMenu"
        class="absolute right-0 top-full z-50 mt-1 w-48 rounded-lg border border-slate-200 bg-white shadow-lg dark:border-slate-700 dark:bg-slate-800"
      >
        <div class="py-1">
          <button
            class="flex w-full items-center gap-3 px-4 py-2 text-left text-sm text-slate-700 transition-colors hover:bg-slate-50 dark:text-slate-300 dark:hover:bg-slate-700"
            @click="handleQuickMessage"
          >
            <i class="i-lucide-mail h-4 w-4" />
            <span>{{ t('KANBAN.CARD.QUICK_MESSAGE') }}</span>
          </button>

          <button
            class="flex w-full items-center gap-3 px-4 py-2 text-left text-sm text-slate-700 transition-colors hover:bg-slate-50 dark:text-slate-300 dark:hover:bg-slate-700"
            @click="handleViewContact"
          >
            <i class="i-lucide-user h-4 w-4" />
            <span>{{ t('KANBAN.CARD.VIEW_CONTACT') }}</span>
          </button>
        </div>
      </div>
    </div>

    <!-- Status Badge (Won/Lost) -->
    <div
      v-if="statusConfig"
      class="mb-2 flex items-center gap-1 rounded-lg px-2 py-1"
      :class="[statusConfig.color]"
    >
      <i class="h-3 w-3" :class="[statusConfig.icon]" />
      <span class="text-xs font-semibold">{{ statusConfig.label }}</span>
    </div>

    <!-- Priority Badge -->
    <div class="mb-2 flex items-center justify-between">
      <span
        :class="priorityColor"
        class="inline-block rounded-full px-2 py-0.5 text-xs font-medium capitalize"
      >
        {{ priority }}
      </span>
      <span
        v-if="conversationId"
        class="text-xs text-slate-500 dark:text-slate-400"
      >
        #{{ conversationId }}
      </span>
    </div>

    <!-- Title -->
    <h4 class="mb-1 font-semibold text-slate-900 dark:text-slate-25">
      {{ title }}
    </h4>

    <!-- Description -->
    <p
      v-if="description"
      class="mb-2 text-sm text-slate-600 dark:text-slate-400"
    >
      {{ truncateText(description) }}
    </p>

    <!-- Labels -->
    <div v-if="labels.length > 0" class="mb-2 flex flex-wrap gap-1">
      <span
        v-for="label in labels.slice(0, 3)"
        :key="label"
        class="inline-block rounded-full bg-blue-100 px-2 py-0.5 text-xs text-blue-700 dark:bg-blue-900 dark:text-blue-300"
      >
        {{ label }}
      </span>
      <span
        v-if="labels.length > 3"
        class="inline-block rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-700 dark:bg-slate-700 dark:text-slate-300"
      >
        +{{ labels.length - 3 }}
      </span>
    </div>

    <!-- Footer -->
    <div
      class="mt-2 flex items-center justify-between border-t border-slate-100 pt-2 dark:border-slate-700"
    >
      <!-- Assigned Agents -->
      <div class="flex -space-x-2">
        <div
          v-for="(agent, index) in assignedAgents.slice(0, 3)"
          :key="index"
          class="flex h-6 w-6 items-center justify-center rounded-full bg-slate-300 text-xs font-medium text-slate-700 ring-2 ring-white dark:bg-slate-600 dark:text-slate-200 dark:ring-slate-800"
          :title="agent.name"
        >
          {{ agent.name?.charAt(0).toUpperCase() || '?' }}
        </div>
        <div
          v-if="assignedAgents.length > 3"
          class="flex h-6 w-6 items-center justify-center rounded-full bg-slate-200 text-xs font-medium text-slate-700 ring-2 ring-white dark:bg-slate-700 dark:text-slate-300 dark:ring-slate-800"
        >
          +{{ assignedAgents.length - 3 }}
        </div>
      </div>

      <!-- Checklist Count (if exists) -->
      <div
        v-if="item.checklist && item.checklist.length > 0"
        class="flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400"
      >
        <span class="i-lucide-check-square" />
        {{ item.checklist.filter(c => c.checked).length }}/{{
          item.checklist.length
        }}
      </div>
    </div>
  </div>
</template>
