<script setup>
import { ref, onMounted, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useConfig } from 'dashboard/composables/useConfig';
import FunnelsHeader from './FunnelsHeader.vue';
import Modal from '../../../../components/Modal.vue';
import FunnelAPI from '../../../../api/funnel';
import FunnelForm from './FunnelForm.vue';
import { emitter } from 'shared/helpers/mitt';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const { isStacklab } = useConfig();
const loading = ref(false);
const funnels = ref([]);
const isLimitReached = ref(false);

// Estado para os modais
const showDeleteModal = ref(false);
const funnelToDelete = ref(null);

// Estado para edição inline
const isEditingMode = ref(false);
const funnelBeingEdited = ref(null);

// Estado para criação de novo funil
const isCreatingMode = ref(false);

// Prop para detectar modo de criação
const props = defineProps({
  createMode: {
    type: Boolean,
    default: false,
  },
});

// Watcher para detectar quando deve iniciar o modo de criação
watch(() => props.createMode, (newValue) => {
  if (newValue) {
    startCreate();
  }
});

const refreshFunnelData = async () => {
  loading.value = true;
  try {
    const response = await FunnelAPI.get();
    const apiFunnels = response.data || [];

    funnels.value = apiFunnels.map(funnel => {
      // Garantir que os estágios tenham sempre posição definida
      const stages = Object.entries(funnel.stages || {}).reduce(
        (acc, [id, stage]) => ({
          ...acc,
          [id]: {
            ...stage,
            id,
            position: parseInt(stage.position, 10) || 0,
            message_templates: stage.message_templates || [],
          },
        }),
        {}
      );
      return {
        ...funnel,
        stages,
      };
    });

    isLimitReached.value = !isStacklab && funnels.value.length >= 2;
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: 'Erro ao carregar dados dos funis.',
      action: { type: 'error' },
    });
  } finally {
    loading.value = false;
  }
};

const confirmDelete = funnel => {
  funnelToDelete.value = funnel;
  showDeleteModal.value = true;
};

const handleDelete = async () => {
  try {
    loading.value = true;
    await FunnelAPI.delete(funnelToDelete.value.id);
    await refreshFunnelData(); // Atualiza a partir da API

    emitter.emit('newToastMessage', {
      message: 'Funil excluído com sucesso',
      action: { type: 'success' },
    });

    showDeleteModal.value = false;
    funnelToDelete.value = null;
  } catch (error) {
    emitter.emit('newToastMessage', {
      message: t('KANBAN.ERRORS.DELETE_FUNNEL_WITH_ITEMS'),
      action: { type: 'error' },
    });
  } finally {
    loading.value = false;
  }
};

const startEdit = funnel => {
  funnelBeingEdited.value = {
    ...funnel,
    id: String(funnel.id),
    stages: Object.entries(funnel.stages || {}).reduce(
      (acc, [key, stage]) => ({
        ...acc,
        [String(key)]: {
          ...stage,
          id: String(stage.id || key),
        },
      }),
      {}
    ),
    settings: funnel.settings || {}, // Preserva todas as configurações
    agents: funnel.settings?.agents || [], // Carrega os agentes do settings
  };

  isEditingMode.value = true;
  isCreatingMode.value = false;

  // Adicionar parâmetro 'funnel' na URL
  const currentQuery = { ...router.currentRoute.value.query };
  currentQuery.funnel = funnel.id;
  router.replace({ query: currentQuery });
};

const startCreate = () => {
  funnelBeingEdited.value = null;
  isEditingMode.value = false;
  isCreatingMode.value = true;

  // Remover parâmetro 'funnel' da URL quando criando novo funil
  const currentQuery = { ...router.currentRoute.value.query };
  delete currentQuery.funnel;
  router.replace({ query: currentQuery });
};

// Inicia criação com dados de template
const startCreateFromTemplate = templateData => {
  funnelBeingEdited.value = null;
  isEditingMode.value = false;
  isCreatingMode.value = true;
  // Guarda template no ref do formulário após mount via prop
  initialFormData.value = templateData;

  // Remover parâmetro 'funnel' da URL quando criando novo funil
  const currentQuery = { ...router.currentRoute.value.query };
  delete currentQuery.funnel;
  router.replace({ query: currentQuery });
};

// Estado para metadados do funil sendo editado
const funnelMetadata = ref({
  updated_at: null,
  name: '',
});

const handleMetadataUpdated = metadata => {
  funnelMetadata.value = metadata;
};

const handleEdit = async updatedFunnel => {
  try {
    // Apenas atualiza a lista de funis e fecha o modo de edição/criação
    // O formulário já fez o update/create na API
    await refreshFunnelData();

    const message = isCreatingMode.value ? 'Funil criado com sucesso' : 'Funil atualizado com sucesso';
    emitter.emit('newToastMessage', {
      message,
      action: { type: 'success' },
    });

    isEditingMode.value = false;
    isCreatingMode.value = false;
    funnelBeingEdited.value = null;
    funnelMetadata.value = { updated_at: null, name: '' };

    // Remover parâmetro 'funnel' da URL quando sair do modo de edição/criação
    const currentQuery = { ...router.currentRoute.value.query };
    delete currentQuery.funnel;
    router.replace({ query: currentQuery });
  } catch (error) {
    const message = isCreatingMode.value ? 'Erro ao criar funil' : 'Erro ao atualizar a lista de funis';
    emitter.emit('newToastMessage', {
      message,
      action: { type: 'error' },
    });
  }
};

const duplicateFunnel = async funnel => {
  try {
    loading.value = true;
    const timestamp = Date.now();

    // Gera novos IDs para as etapas
    const newStages = Object.entries(funnel.stages).reduce(
      (acc, [_, stage]) => {
        const newId = `stage_${timestamp}_${stage.position}`;
        return {
          ...acc,
          [newId]: {
            ...stage,
            id: newId,
            message_templates: stage.message_templates?.map(template => ({
              ...template,
              id: `template_${timestamp}_${template.id}`,
              stage_id: newId,
            })),
          },
        };
      },
      {}
    );

    const newFunnel = {
      name: `${funnel.name} (cópia)`,
      description: funnel.description,
      active: funnel.active,
      stages: newStages,
      settings: {
        ...funnel.settings,
        agents: funnel.settings?.agents || [],
      },
    };

    await FunnelAPI.create(newFunnel);
    await refreshFunnelData(); // Atualiza a partir da API
  } catch (error) {
  } finally {
    loading.value = false;
  }
};

// Função para ordenar as etapas de um funil por posição
const getSortedStages = stages => {
  if (!stages) return [];

  // Converter objeto de etapas em array
  const stagesArray = Object.entries(stages)
    .map(([id, stage]) => ({
      id,
      ...stage,
      position: parseInt(stage.position, 10) || 0,
    }))
    .sort((a, b) => a.position - b.position);

  return stagesArray;
};

// Funções para controlar o FunnelForm através do header
const handleSaveFromHeader = () => {
  // Verifica se estamos em modo de edição ou criação
  if (!isEditingMode.value && !isCreatingMode.value) {
    console.warn('Tentativa de salvar sem estar em modo de edição ou criação');
    return;
  }

  // Emite evento personalizado para o FunnelForm
  if (funnelFormRef.value && funnelFormRef.value.$el) {
    funnelFormRef.value.$el.dispatchEvent(new CustomEvent('save-form'));
  } else {
    console.error('FunnelForm ref não está disponível');
  }
};

const handleDiscardFromHeader = () => {
  isEditingMode.value = false;
  isCreatingMode.value = false;
  funnelBeingEdited.value = null;
  funnelMetadata.value = { updated_at: null, name: '' };

  // Remover parâmetro 'funnel' da URL quando descartar mudanças
  const currentQuery = { ...router.currentRoute.value.query };
  delete currentQuery.funnel;
  router.replace({ query: currentQuery });
};

const handleCloseForm = () => {
  isEditingMode.value = false;
  isCreatingMode.value = false;
  funnelBeingEdited.value = null;
  funnelMetadata.value = { updated_at: null, name: '' };

  // Remover parâmetro 'funnel' da URL quando fechar formulário
  const currentQuery = { ...router.currentRoute.value.query };
  delete currentQuery.funnel;
  router.replace({ query: currentQuery });
};

const handleBack = () => {
  isEditingMode.value = false;
  isCreatingMode.value = false;
  funnelBeingEdited.value = null;
  funnelMetadata.value = { updated_at: null, name: '' };

  // Remover parâmetro 'funnel' da URL quando voltar
  const currentQuery = { ...router.currentRoute.value.query };
  delete currentQuery.funnel;
  router.replace({ query: currentQuery });
};


// Refs para controlar o FunnelForm
const funnelFormRef = ref(null);
const initialFormData = ref(null);

const emit = defineEmits(['switch-view']);

onMounted(async () => {
  await refreshFunnelData(); // Busca inicial a partir da API

  // Verificar se há parâmetro 'funnel' na URL para abrir em modo de edição
  const currentQuery = router.currentRoute.value.query;
  if (currentQuery.funnel) {
    const funnelId = currentQuery.funnel;
    const funnel = funnels.value.find(f => f.id == funnelId);
    if (funnel) {
      startEdit(funnel);
    }
  }
});
</script>

<template>
  <div class="flex flex-col h-full bg-white dark:bg-slate-900 p-4">
    <FunnelsHeader
      :editing-funnel="isEditingMode ? funnelBeingEdited : null"
      :funnel-metadata="funnelMetadata"
      :is-creating="isCreatingMode"
      @switch-view="view => emit('switch-view', view)"
      @back="handleBack"
      @funnel-created="refreshFunnelData"
      @save-funnel="handleSaveFromHeader"
      @discard-changes="handleDiscardFromHeader"
      @create-new-funnel="startCreate"
      @create-from-template="startCreateFromTemplate"
    />

    <div class="funnels-content flex-1 overflow-y-auto">
      <!-- Renderiza FunnelForm quando estiver editando ou criando -->
      <FunnelForm
        ref="funnelFormRef"
        v-if="isEditingMode || isCreatingMode"
        :is-editing="isEditingMode"
        :funnel-id="isEditingMode ? funnelBeingEdited.id : null"
        :initial-data="!isEditingMode ? initialFormData : null"
        @saved="handleEdit"
        @metadata-updated="handleMetadataUpdated"
        @close="handleCloseForm"
      />

      <!-- Renderiza lista de funis quando NÃO estiver editando -->
      <template v-else>
        <!-- Alerta de Limite -->
        <div
          v-if="isLimitReached"
          class="mb-6 p-4 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg"
        >
          <div class="flex items-center gap-3">
            <div class="shrink-0">
              <fluent-icon
                icon="warning"
                size="20"
                class="text-amber-500 dark:text-amber-300"
              />
            </div>
            <div class="flex-1">
              <p class="text-amber-800 dark:text-amber-100 font-medium">
                Limite de Funis Atingido
              </p>
              <p class="text-amber-700 dark:text-amber-200 text-sm mt-1">
                Você atingiu o limite de 2 funis. Atualize para a versão PRO para
                criar mais funis.
              </p>
            </div>
          </div>
        </div>

        <!-- Loading State -->
        <div v-if="loading" class="flex justify-center items-center py-12">
          <span class="loading-spinner" />
        </div>

        <!-- Empty State -->
        <div
          v-else-if="!funnels.length"
          class="flex flex-col items-center justify-center py-12 text-slate-600"
        >
          <fluent-icon icon="task" size="48" class="mb-4" />
          <p class="text-lg">Nenhum funil encontrado</p>
          <p class="text-sm">
            Crie um novo funil para começar a organizar seus itens
          </p>
        </div>

        <!-- Funnels List -->
        <div v-else class="grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
          <div
            v-for="funnel in funnels"
            :key="funnel.id"
            class="funnel-card p-4 border border-slate-100 dark:border-slate-700 rounded-lg hover:bg-slate-50 dark:hover:bg-slate-800 relative"
          >
            <!-- Botões de Ação -->
            <div class="absolute top-4 right-4 flex items-center gap-1">
              <Button
                variant="ghost"
                color="slate"
                size="sm"
                @click="startEdit(funnel)"
              >
                <template #icon>
                  <fluent-icon icon="edit" size="16" />
                </template>
              </Button>
              <Button
                variant="ghost"
                color="slate"
                size="sm"
                @click="duplicateFunnel(funnel)"
              >
                <template #icon>
                  <fluent-icon icon="copy" size="16" />
                </template>
              </Button>
              <Button
                variant="ghost"
                color="ruby"
                size="sm"
                @click="confirmDelete(funnel)"
              >
                <template #icon>
                  <fluent-icon icon="delete" size="16" />
                </template>
              </Button>
            </div>

            <div class="flex flex-col gap-4">
              <!-- Informações básicas -->
              <div class="flex items-center gap-2">
                <span class="text-xs text-slate-400 select-all"
                  >#{{ funnel.id }}</span
                >
                <h3 class="text-lg font-medium">{{ funnel.name }}</h3>
                <span
                  :class="[
                    'text-xs px-2 py-0.5 rounded-full',
                    funnel.active
                      ? 'bg-green-100 text-green-700'
                      : 'bg-red-100 text-red-700',
                  ]"
                >
                  {{ funnel.active ? 'Ativo' : 'Inativo' }}
                </span>
              </div>

              <!-- Data de criação -->
              <p class="text-xs text-slate-500">
                Criado em: {{ new Date(funnel.created_at).toLocaleDateString() }}
              </p>

              <!-- Etapas -->
              <div class="flex flex-wrap gap-2">
                <span
                  v-for="stage in getSortedStages(funnel.stages)"
                  :key="stage.id"
                  class="px-2 py-1 text-xs font-medium rounded-full flex items-center gap-1 group relative"
                  :style="{
                    backgroundColor: `${stage.color}20`,
                    color: stage.color,
                  }"
                >
                  {{ stage.name }}
                  <!-- Badge de templates se houver -->
                  <span
                    v-if="stage.message_templates?.length"
                    class="ml-1 px-1.5 text-[10px] rounded-full bg-white/50"
                  >
                    {{ stage.message_templates.length }}
                  </span>

                  <!-- Tooltip com templates -->
                  <div
                    v-if="stage.message_templates?.length"
                    class="absolute hidden group-hover:block bg-white dark:bg-slate-800 shadow-lg rounded-lg p-3 z-10 min-w-[250px] top-full left-0 mt-1"
                  >
                    <div class="flex items-center gap-2 mb-2">
                      <fluent-icon icon="chat" size="16" class="text-woot-500" />
                      <p class="text-xs font-medium">Templates de Mensagem</p>
                    </div>
                    <div class="space-y-2">
                      <div
                        v-for="template in stage.message_templates"
                        :key="template.id"
                        class="p-2 bg-slate-50 dark:bg-slate-700 rounded"
                      >
                        <div class="flex items-center justify-between mb-1">
                          <p class="text-xs font-medium">{{ template.title }}</p>
                          <span
                            v-if="template.webhook?.enabled"
                            class="text-[10px] px-1.5 py-0.5 rounded bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300"
                          >
                            Webhook
                          </span>
                        </div>
                        <p
                          class="text-[11px] text-slate-600 dark:text-slate-400 line-clamp-2"
                        >
                          {{ template.content }}
                        </p>
                      </div>
                    </div>
                  </div>
                </span>
              </div>

              <!-- Agentes -->
              <div
                v-if="funnel.settings?.agents?.length"
                class="flex flex-wrap gap-2"
              >
                <div
                  v-for="agent in funnel.settings.agents"
                  :key="agent.id"
                  class="flex items-center gap-2 px-2 py-1 bg-slate-100 dark:bg-slate-800 rounded-lg"
                >
                  <Avatar :name="agent.name" :src="agent.thumbnail" :size="20" />
                  <span class="text-xs text-slate-700 dark:text-slate-300">
                    {{ agent.name }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </template>
    </div>


    <!-- Modal de Confirmação de Exclusão -->
    <Modal
      v-model:show="showDeleteModal"
      :on-close="() => (showDeleteModal = false)"
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4">
          {{ t('KANBAN.FUNNELS.DELETE.TITLE') }}
        </h3>
        <p class="text-sm text-slate-600 mb-6">
          {{
            t('KANBAN.FUNNELS.DELETE.DESCRIPTION', {
              name: funnelToDelete?.name,
            })
          }}
        </p>
        <div class="flex justify-end gap-2">
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            @click="showDeleteModal = false"
          >
            {{ t('KANBAN.CANCEL') }}
          </Button>
          <Button
            variant="solid"
            color="ruby"
            size="sm"
            :isLoading="loading"
            @click="handleDelete"
          >
            {{ t('KANBAN.DELETE') }}
          </Button>
        </div>
      </div>
    </Modal>
  </div>
</template>

<style lang="scss" scoped>
.loading-spinner {
  width: 40px;
  height: 40px;
  border: 3px solid var(--color-border-light);
  border-top: 3px solid var(--color-woot);
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(360deg);
  }
}

.funnels-content {
  min-height: 0; // Importante para o scroll funcionar
}

:deep(.funnel-modal) {
  .modal-container {
    @apply max-w-[1024px] w-[90vw];
  }
}
</style>
