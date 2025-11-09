<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import MessageTemplatesHeader from './MessageTemplatesHeader.vue';
import FunnelAPI from '../../../../api/funnel';
import Modal from '../../../../components/Modal.vue';
import MessageTemplateForm from './MessageTemplateForm.vue';

const emit = defineEmits(['switch-view']);
const { t } = useI18n();

const loading = ref(false);
const funnels = ref([]);
const error = ref(null);
const selectedFunnelId = ref(null);
const isComponentMounted = ref(true);

// Estado para controlar o modal de confirmação
const showDeleteModal = ref(false);
const templateToDelete = ref(null);
const stageToDeleteFrom = ref(null);

// Estado para controlar o modal de edição
const showEditModal = ref(false);
const templateToEdit = ref(null);

// Estado para controlar o modal de criação
const showCreateModal = ref(false);
const newTemplateData = ref(null);

// Busca os funis e seus templates
const fetchFunnels = async () => {
  try {
    loading.value = true;
    if (!isComponentMounted.value) return;
    const response = await FunnelAPI.get();
    funnels.value = response.data;

    // Seleciona o primeiro funil por padrão
    if (funnels.value.length && !selectedFunnelId.value) {
      selectedFunnelId.value = funnels.value[0].id;
    }
  } catch (err) {
    if (!isComponentMounted.value) return;
    error.value = err.message;
  } finally {
    if (!isComponentMounted.value) return;
    loading.value = false;
  }
};

// Retorna o funil selecionado e suas etapas organizadas
const selectedFunnel = computed(() => {
  const funnel = funnels.value.find(f => f.id === selectedFunnelId.value);
  if (!funnel) return null;

  return {
    ...funnel,
    stages: Object.entries(funnel.stages || {})
      .map(([id, stage]) => ({
        id,
        ...stage,
        message_templates: stage.message_templates || [],
      }))
      .sort((a, b) => a.position - b.position),
  };
});

const handleTemplateCreated = async () => {
  try {
    loading.value = true;
    if (!isComponentMounted.value) return;
    await fetchFunnels();
  } catch (err) {
    if (!isComponentMounted.value) return;
    error.value = err.message;
  } finally {
    if (!isComponentMounted.value) return;
    loading.value = false;
  }
};

// Função para truncar texto
const truncateText = (text, length) => {
  if (!text) return '';
  return text.length > length ? `${text.slice(0, length)}...` : text;
};

// Função para abrir o modal de confirmação
const confirmDelete = (template, stageId) => {
  templateToDelete.value = template;
  stageToDeleteFrom.value = stageId;
  showDeleteModal.value = true;
};

// Função para deletar template após confirmação
const handleDeleteTemplate = async () => {
  try {
    loading.value = true;
    const currentFunnel = funnels.value.find(
      f => f.id === selectedFunnelId.value
    );

    if (!currentFunnel) {
      throw new Error('Funil não encontrado');
    }

    const updatedFunnel = { ...currentFunnel };
    const templateIndex = updatedFunnel.stages[
      stageToDeleteFrom.value
    ].message_templates.findIndex(t => t.id === templateToDelete.value.id);

    if (templateIndex > -1) {
      updatedFunnel.stages[stageToDeleteFrom.value].message_templates.splice(
        templateIndex,
        1
      );

      await FunnelAPI.update(currentFunnel.id, updatedFunnel);
      await fetchFunnels();
    }

    // Fecha o modal após deletar
    showDeleteModal.value = false;
  } catch (err) {
    // Erro ao excluir template
    error.value = err.message;
  } finally {
    loading.value = false;
  }
};

// Função para editar template
const handleEditTemplate = (template, stageId) => {
  templateToEdit.value = {
    ...template,
    funnel_id: selectedFunnelId.value,
    stage_id: stageId,
    isEditing: true,
  };
  showEditModal.value = true;
};

// Handler para quando o template é salvo
const handleTemplateSaved = template => {
  showEditModal.value = false;
  handleTemplateCreated(template);
};

// Função para abrir o modal de criação
const openCreateModal = (funnelId, stageId) => {
  newTemplateData.value = {
    funnel_id: funnelId,
    stage_id: stageId,
  };
  showCreateModal.value = true;
};

// Handler para quando o template é criado
const handleNewTemplateCreated = template => {
  showCreateModal.value = false;
  handleTemplateCreated(template);
};

onMounted(() => {
  isComponentMounted.value = true;
  fetchFunnels();
});

onBeforeUnmount(() => {
  isComponentMounted.value = false;
  selectedFunnelId.value = null;
  funnels.value = [];
  error.value = null;
  loading.value = false;
});
</script>

<template>
  <div class="message-templates">
    <MessageTemplatesHeader
      @switch-view="view => emit('switch-view', view)"
      @template-created="handleTemplateCreated"
    />

    <div class="message-templates-content">
      <!-- Loading State -->
      <div v-if="loading" class="flex items-center justify-center h-full">
        <span class="loading-spinner" />
      </div>

      <!-- Error State -->
      <div
        v-else-if="error"
        class="flex flex-col items-center justify-center h-full text-center p-4"
      >
        <fluent-icon icon="error" size="24" class="text-n-ruby-9 mb-2" />
        <p class="text-slate-600 dark:text-slate-400">
          {{ t('KANBAN.MESSAGE_TEMPLATES.ERROR') }}
        </p>
        <woot-button
          variant="clear"
          size="small"
          class="mt-2"
          @click="fetchFunnels"
        >
          {{ t('RETRY') }}
        </woot-button>
      </div>

      <!-- Empty State -->
      <div
        v-else-if="!funnels.length"
        class="flex flex-col items-center justify-center h-full text-center p-4"
      >
        <fluent-icon icon="document" size="24" class="text-slate-400 mb-2" />
        <h3 class="text-lg font-medium mb-1">
          {{ t('KANBAN.MESSAGE_TEMPLATES.EMPTY') }}
        </h3>
        <p class="text-sm text-slate-600 dark:text-slate-400">
          {{ t('KANBAN.MESSAGE_TEMPLATES.EMPTY_DESCRIPTION') }}
        </p>
      </div>

      <!-- Templates List -->
      <div v-else class="templates-container">
        <!-- Funnel Tabs -->
        <div class="funnel-tabs">
          <button
            v-for="funnel in funnels"
            :key="funnel.id"
            class="funnel-tab"
            :class="{ active: funnel.id === selectedFunnelId }"
            @click="selectedFunnelId = funnel.id"
          >
            {{ funnel.name }}
          </button>
        </div>

        <!-- Selected Funnel Content -->
        <div v-if="selectedFunnel" class="funnel-content">
          <div class="stages-grid">
            <div
              v-for="stage in selectedFunnel.stages"
              :key="stage.id"
              class="stage-card"
            >
              <!-- Stage Header -->
              <div class="stage-header">
                <div
                  class="stage-color"
                  :style="{ backgroundColor: stage.color }"
                />
                <h4 class="stage-title">{{ stage.name }}</h4>
                <woot-button
                  variant="clear"
                  size="small"
                  class="add-template-button"
                  @click="openCreateModal(selectedFunnel.id, stage.id)"
                >
                  <fluent-icon icon="add" size="16" />
                </woot-button>
              </div>

              <!-- Templates List -->
              <div class="templates-list">
                <div
                  v-for="template in stage.message_templates"
                  :key="template.id"
                  class="template-item"
                >
                  <div class="template-info">
                    <div class="template-row">
                      <span class="template-title" :title="template.title">
                        {{ truncateText(template.title, 25) }}
                      </span>
                      <span class="template-separator">•</span>
                      <span class="template-content" :title="template.content">
                        {{ truncateText(template.content, 25) }}
                      </span>
                      <span class="template-separator">•</span>
                      <span class="template-date">
                        {{ new Date(template.created_at).toLocaleDateString() }}
                      </span>
                      <div class="template-badges">
                        <span
                          class="badge edit-badge"
                          title="Editar Template"
                          @click.stop="handleEditTemplate(template, stage.id)"
                        >
                          <fluent-icon icon="edit" size="12" />
                        </span>
                        <span
                          v-if="template.webhook.enabled"
                          class="badge"
                          title="Webhook Ativo"
                        >
                          <fluent-icon icon="globe" size="12" />
                        </span>
                        <span
                          v-if="template.conditions.enabled"
                          class="badge"
                          title="Condições Ativas"
                        >
                          <fluent-icon icon="filter" size="12" />
                        </span>
                        <span
                          class="badge delete-badge"
                          title="Excluir Template"
                          @click.stop="confirmDelete(template, stage.id)"
                        >
                          <fluent-icon icon="delete" size="12" />
                        </span>
                      </div>
                    </div>
                  </div>
                </div>

                <div
                  v-if="!stage.message_templates?.length"
                  class="empty-templates"
                >
                  {{ t('KANBAN.MESSAGE_TEMPLATES.NO_TEMPLATES') }}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal de Confirmação -->
    <Modal
      v-model:show="showDeleteModal"
      :on-close="() => (showDeleteModal = false)"
    >
      <div class="delete-modal">
        <h3 class="modal-title">
          {{ t('KANBAN.DELETE.TITLE') }}
        </h3>
        <p class="modal-description">
          {{
            t('KANBAN.DELETE.DESCRIPTION', {
              name: templateToDelete?.title,
            })
          }}
        </p>
        <div class="modal-actions">
          <woot-button
            variant="clear"
            color-scheme="secondary"
            @click="showDeleteModal = false"
          >
            {{ t('KANBAN.ACTIONS.CANCEL') }}
          </woot-button>
          <woot-button
            variant="primary"
            color-scheme="danger"
            :loading="loading"
            @click="handleDeleteTemplate"
          >
            {{ t('KANBAN.DELETE.TITLE') }}
          </woot-button>
        </div>
      </div>
    </Modal>

    <!-- Modal de Edição -->
    <Modal
      v-model:show="showEditModal"
      :on-close="() => (showEditModal = false)"
      class="template-modal"
    >
      <div class="p-6">
        <MessageTemplateForm
          :initial-data="templateToEdit"
          :is-editing="true"
          :funnels="funnels"
          @saved="handleTemplateSaved"
          @close="showEditModal = false"
        />
      </div>
    </Modal>

    <!-- Modal de Criação -->
    <Modal
      v-model:show="showCreateModal"
      :on-close="() => (showCreateModal = false)"
      class="template-modal"
    >
      <div class="p-6">
        <MessageTemplateForm
          :initial-data="newTemplateData"
          :is-editing="false"
          :funnels="funnels"
          @saved="handleNewTemplateCreated"
          @close="showCreateModal = false"
        />
      </div>
    </Modal>
  </div>
</template>

<style lang="scss" scoped>
.message-templates {
  @apply flex flex-col h-full w-full bg-white dark:bg-slate-900;
  padding: 16px;
}

.message-templates-content {
  @apply flex-1 p-4 overflow-hidden;
}

.loading-spinner {
  @apply w-8 h-8 border-2 border-slate-200 border-t-woot-500 rounded-full animate-spin;
}

.templates-container {
  @apply h-full flex flex-col;
}

.funnel-tabs {
  @apply flex gap-2 mb-4 overflow-x-auto;
  scrollbar-width: none;
  &::-webkit-scrollbar {
    display: none;
  }
}

.funnel-tab {
  @apply px-4 py-2 rounded-lg text-sm font-medium text-slate-600 dark:text-slate-400 whitespace-nowrap transition-colors;

  &:hover {
    @apply bg-slate-100 dark:bg-slate-800;
  }

  &.active {
    @apply bg-woot-500 text-white;
  }
}

.funnel-content {
  @apply flex-1 overflow-y-auto;
}

.stages-grid {
  @apply grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4;
}

.stage-card {
  @apply bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg flex flex-col;
  min-height: 200px;
}

.stage-header {
  @apply flex items-center gap-2 p-3 border-b border-slate-200 dark:border-slate-700;
}

.stage-color {
  @apply w-3 h-3 rounded-full flex-shrink-0;
}

.stage-title {
  @apply font-medium flex-1 truncate;
}

.add-template-button {
  @apply opacity-0 group-hover:opacity-100 transition-opacity;
}

.stage-card:hover .add-template-button {
  @apply opacity-100;
}

.templates-list {
  @apply p-3 space-y-2 flex-1 overflow-y-auto;
}

.template-item {
  @apply p-2 bg-white dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700 hover:border-woot-500 dark:hover:border-woot-500 transition-colors;
}

.template-row {
  @apply flex items-center gap-2 text-xs;
}

.template-title {
  @apply font-medium text-slate-800 dark:text-slate-200 truncate;
  max-width: 120px;
}

.template-content {
  @apply text-slate-600 dark:text-slate-400 truncate flex-1;
}

.template-separator {
  @apply text-slate-400 dark:text-slate-600;
}

.template-date {
  @apply text-slate-500 whitespace-nowrap;
}

.template-badges {
  @apply flex items-center gap-1 ml-2;
}

.badge {
  @apply flex items-center justify-center w-5 h-5 rounded-full bg-slate-100 dark:bg-slate-700 text-slate-500;

  &:hover {
    @apply bg-slate-200 dark:bg-slate-600;
  }
}

.empty-templates {
  @apply text-sm text-center text-slate-500 dark:text-slate-400 py-4 bg-slate-50 dark:bg-slate-800 rounded-lg border border-dashed border-slate-300 dark:border-slate-700;
}

.delete-badge {
  @apply bg-n-ruby-3 text-n-ruby-9 dark:bg-n-ruby-8 dark:text-n-ruby-4;

  &:hover {
    @apply bg-n-ruby-4 dark:bg-n-ruby-7;
  }
}

.badge {
  @apply cursor-pointer;
}

.delete-modal {
  @apply p-6;
}

.modal-title {
  @apply text-lg font-medium text-slate-800 dark:text-slate-200 mb-2;
}

.modal-description {
  @apply text-sm text-slate-600 dark:text-slate-400 mb-6;
}

.modal-actions {
  @apply flex justify-end gap-2;
}

.edit-badge {
  @apply bg-woot-50 text-woot-500 dark:bg-woot-900 dark:text-woot-400;

  &:hover {
    @apply bg-woot-100 dark:bg-woot-800;
  }
}

:deep(.template-modal) {
  .modal-container {
    @apply max-w-[1280.6px] w-[103.5vw];
  }
}
</style>
