<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { default as FluentIcon } from 'shared/components/FluentIcon/Icon.vue';
import dashboardIcons from 'shared/components/FluentIcon/dashboard-icons.json';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  editingOffer: {
    type: Object,
    default: null,
  },
  offerMetadata: {
    type: Object,
    default: () => ({
      updated_at: null,
      name: '',
    }),
  },
  isCreating: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'switch-view',
  'back',
  'offer-created',
  'save-offer',
  'discard-changes',
  'create-new-offer',
]);

const { t } = useI18n();

const copiedId = ref(false);

const handleBack = () => {
  // Se estiver editando ou criando, emitir 'back' para voltar à lista de ofertas
  // Caso contrário, emitir 'switch-view' para voltar ao kanban
  if (props.editingOffer || props.isCreating) {
    emit('back');
  } else {
    emit('switch-view', 'kanban');
  }
};

const handleSaveOffer = () => {
  emit('save-offer');
};

const handleDiscardChanges = () => {
  emit('discard-changes');
};

const copyOfferId = async () => {
  if (props.editingOffer?.id) {
    await navigator.clipboard.writeText(props.editingOffer.id.toString());
    copiedId.value = true;
    setTimeout(() => {
      copiedId.value = false;
    }, 2000);
  }
};
</script>

<template>
  <header class="offers-header">
    <div class="flex items-center justify-between">
      <div class="flex items-center gap-4">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="lucide lucide-chevron-left-icon lucide-chevron-left cursor-pointer text-slate-600 dark:text-slate-400"
          @click="handleBack"
        >
          <path d="m15 18-6-6 6-6" />
        </svg>
        <div class="flex items-center gap-4">
          <h1 class="text-base font-medium flex items-center gap-2">
            <span class="hidden md:inline">{{
              editingOffer
                ? t('KANBAN.OFFERS.MANAGER.EDITING')
                : isCreating
                  ? t('KANBAN.OFFERS.MANAGER.CREATING')
                  : t('KANBAN.OFFERS.TITLE')
            }}</span>
            <span v-if="editingOffer">{{ editingOffer.name }}</span>
            <span v-if="isCreating">{{
              t('KANBAN.OFFERS.MANAGER.NEW_OFFER')
            }}</span>
            <span
              v-if="editingOffer"
              class="hidden md:flex px-2 py-1 text-xs bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 rounded flex items-center gap-2 cursor-pointer hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors"
              :title="t('KANBAN.OFFERS.MANAGER.COPY')"
              @click="copyOfferId"
            >
              <span
                class="text-[10px] text-slate-500 dark:text-slate-400 mr-1"
                >{{ t('KANBAN.OFFERS.MANAGER.ID') }}</span>{{ editingOffer.id }}
              <svg
                v-if="!copiedId"
                xmlns="http://www.w3.org/2000/svg"
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="lucide lucide-copy-icon lucide-copy"
              >
                <rect width="14" height="14" x="8" y="8" rx="2" ry="2" />
                <path
                  d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"
                />
              </svg>
              <svg
                v-else
                xmlns="http://www.w3.org/2000/svg"
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="lucide lucide-circle-check-big-icon lucide-circle-check-big"
              >
                <path d="M21.801 10A10 10 0 1 1 17 3.335" />
                <path d="m9 11 3 3L22 4" />
              </svg>
              <span class="text-[10px] text-slate-500 dark:text-slate-400">{{
                copiedId
                  ? t('KANBAN.OFFERS.MANAGER.COPIED')
                  : t('KANBAN.OFFERS.MANAGER.COPY')
              }}</span>
            </span>
          </h1>
          <div
            v-if="editingOffer && offerMetadata.updated_at"
            class="hidden md:block text-xs text-slate-500 dark:text-slate-400"
          >
            {{ t('KANBAN.OFFERS.MANAGER.UPDATED_AT') }}
            {{ new Date(offerMetadata.updated_at).toLocaleString() }}
          </div>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <!-- Botões quando NÃO está editando nem criando -->
        <template v-if="!editingOffer && !isCreating">
          <Button
            variant="solid"
            color="blue"
            size="sm"
            @click="emit('create-new-offer')"
          >
            <template #icon>
              <FluentIcon icon="add" size="20" :icons="dashboardIcons" />
            </template>
            <span>{{ t('KANBAN.OFFERS.MANAGER.NEW_OFFER') }}</span>
          </Button>
        </template>

        <!-- Botões quando ESTÁ editando ou criando -->
        <template v-else>
          <div class="flex items-center gap-3">
            <Button
              variant="ghost"
              color="slate"
              size="sm"
              @click="handleDiscardChanges"
            >
              <span>{{ t('KANBAN.OFFERS.MANAGER.DISCARD') }}</span>
            </Button>
          </div>
          <Button
            variant="solid"
            color="blue"
            size="sm"
            @click="handleSaveOffer"
          >
            <span>{{ t('KANBAN.OFFERS.MANAGER.SAVE') }}</span>
          </Button>
        </template>
      </div>
    </div>
  </header>
</template>

<style lang="scss" scoped>
.offers-header {
  padding: var(--space-normal);
  border-bottom: 1px solid var(--color-border);
  background: var(--white);
  margin-bottom: 16px;

  @apply dark:border-slate-800 dark:bg-slate-900;

  h1 {
    @apply dark:text-slate-100;
  }
}
</style>
