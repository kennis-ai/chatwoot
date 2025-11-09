<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Modal from '../../../../components/Modal.vue';
import MessageTemplateForm from './MessageTemplateForm.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['switch-view', 'template-created']);
const { t } = useI18n();
const showNewTemplateModal = ref(false);

const handleBack = () => {
  emit('switch-view', 'kanban');
};

const handleTemplateCreated = template => {
  showNewTemplateModal.value = false;
  emit('template-created', template);
};
</script>

<template>
  <header class="message-templates-header">
    <div class="flex items-center justify-between">
      <div class="flex items-center gap-4">
        <Button variant="ghost" color="slate" size="sm" @click="handleBack">
          <fluent-icon icon="chevron-left" size="16" />
        </Button>
        <h1 class="text-2xl font-medium">
          {{ t('KANBAN.MESSAGE_TEMPLATES.TITLE') }}
        </h1>
      </div>
      <Button
        variant="solid"
        color="blue"
        size="sm"
        @click="showNewTemplateModal = true"
      >
        <fluent-icon icon="add" size="16" class="mr-2" />
        {{ t('KANBAN.MESSAGE_TEMPLATES.ADD') }}
      </Button>
    </div>

    <Modal
      v-model:show="showNewTemplateModal"
      :on-close="() => (showNewTemplateModal = false)"
      class="template-modal"
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4">
          {{ t('KANBAN.MESSAGE_TEMPLATES.NEW') }}
        </h3>
        <MessageTemplateForm
          @saved="handleTemplateCreated"
          @close="showNewTemplateModal = false"
        />
      </div>
    </Modal>
  </header>
</template>

<style lang="scss" scoped>
.message-templates-header {
  padding: var(--space-normal);
  border-bottom: 1px solid var(--color-border);
  background: var(--white);

  @apply dark:border-slate-800 dark:bg-slate-900;

  h1 {
    @apply dark:text-slate-100;
  }
}

:deep(.template-modal) {
  .modal-container {
    @apply max-w-[1024px] w-[90vw] dark:bg-slate-900;

    h3 {
      @apply dark:text-slate-100;
    }
  }
}
</style>
