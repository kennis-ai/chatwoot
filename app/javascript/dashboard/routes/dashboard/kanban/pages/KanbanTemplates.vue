<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import KanbanTemplateModal from '../components/KanbanTemplateModal.vue';

const store = useStore();
const { t } = useI18n();
const router = useRouter();

const config = computed(() => store.getters['kanban/getConfig']);
const funnels = computed(() => store.getters['kanban/getFunnels']);
const uiFlags = computed(() => store.getters['kanban/getUIFlags']);

const selectedFunnelId = ref(null);
const templates = ref({});
const showTemplateModal = ref(false);
const editingTemplate = ref(null);
const selectedStage = ref(null);

const selectedFunnel = computed(() => {
  return (
    funnels.value.find(f => f.id === selectedFunnelId.value) || funnels.value[0]
  );
});

onMounted(async () => {
  await store.dispatch('kanban/getConfig');

  if (funnels.value.length > 0) {
    selectedFunnelId.value = funnels.value[0].id;
  }

  // Load templates from config
  if (config.value?.config?.templates) {
    templates.value = JSON.parse(JSON.stringify(config.value.config.templates));
  }
});

const getTemplatesForStage = stage => {
  if (!selectedFunnelId.value) return [];
  const key = `${selectedFunnelId.value}_${stage}`;
  return templates.value[key] || [];
};

const openNewTemplateModal = stage => {
  editingTemplate.value = null;
  selectedStage.value = stage;
  showTemplateModal.value = true;
};

const openEditTemplateModal = (template, stage) => {
  editingTemplate.value = template;
  selectedStage.value = stage;
  showTemplateModal.value = true;
};

const closeTemplateModal = () => {
  showTemplateModal.value = false;
  editingTemplate.value = null;
  selectedStage.value = null;
};

const saveTemplates = async () => {
  try {
    const payload = {
      ...config.value,
      config: {
        ...config.value.config,
        templates: templates.value,
      },
    };

    await store.dispatch('kanban/updateConfig', payload);
    useAlert(t('KANBAN.TEMPLATES.SAVED'));
  } catch (error) {
    // Error already handled by store
    useAlert(t('KANBAN.TEMPLATES.ERROR_SAVING'), 'error');
  }
};

const handleTemplateSaved = templateData => {
  const key = `${selectedFunnelId.value}_${selectedStage.value}`;

  if (!templates.value[key]) {
    templates.value[key] = [];
  }

  if (editingTemplate.value) {
    // Update existing
    const index = templates.value[key].findIndex(
      tmpl => tmpl.id === editingTemplate.value.id
    );
    if (index !== -1) {
      templates.value[key][index] = {
        ...templateData,
        id: editingTemplate.value.id,
      };
    }
  } else {
    // Add new
    templates.value[key].push({ ...templateData, id: Date.now() });
  }

  saveTemplates();
  closeTemplateModal();
};

const handleDeleteTemplate = (template, stage) => {
  // eslint-disable-next-line no-restricted-globals, no-alert
  if (!confirm(t('KANBAN.TEMPLATES.CONFIRM_DELETE'))) return;

  const key = `${selectedFunnelId.value}_${stage}`;
  if (templates.value[key]) {
    templates.value[key] = templates.value[key].filter(
      tmpl => tmpl.id !== template.id
    );
    saveTemplates();
  }
};

const navigateToBoard = () => {
  router.push({ name: 'kanban_board' });
};

const handleFunnelChange = funnelId => {
  selectedFunnelId.value = parseInt(funnelId, 10);
};
</script>

<template>
  <div class="flex h-full flex-col">
    <!-- Header -->
    <div
      class="flex items-center justify-between border-b border-slate-100 p-4 dark:border-slate-700"
    >
      <div class="flex items-center gap-4">
        <button
          class="text-slate-600 hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100"
          @click="navigateToBoard"
        >
          <i class="i-lucide-arrow-left h-5 w-5" />
        </button>
        <h1 class="text-2xl font-semibold text-slate-900 dark:text-slate-25">
          {{ t('KANBAN.TEMPLATES.TITLE') }}
        </h1>
      </div>
      <Button
        variant="primary"
        size="small"
        icon="add"
        @click="openNewTemplateModal(null)"
      >
        {{ t('KANBAN.TEMPLATES.ADD_TEMPLATE') }}
      </Button>
    </div>

    <!-- Loading -->
    <div
      v-if="uiFlags.isFetching"
      class="flex h-full items-center justify-center"
    >
      <Spinner />
    </div>

    <!-- Templates Content -->
    <div
      v-else
      class="flex-1 overflow-y-auto bg-slate-50 p-6 dark:bg-slate-900"
    >
      <div class="mx-auto max-w-7xl">
        <!-- Funnel Selector -->
        <div class="mb-6 flex gap-2">
          <button
            v-for="funnel in funnels"
            :key="funnel.id"
            class="rounded-lg px-4 py-2 font-medium transition-colors"
            :class="[
              selectedFunnelId === funnel.id
                ? 'bg-blue-600 text-white'
                : 'bg-white text-slate-600 hover:bg-slate-100 dark:bg-slate-800 dark:text-slate-400 dark:hover:bg-slate-700',
            ]"
            @click="handleFunnelChange(funnel.id)"
          >
            {{ funnel.name }}
          </button>
        </div>

        <!-- Templates Grid -->
        <div
          v-if="selectedFunnel"
          class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
        >
          <div
            v-for="stage in selectedFunnel.stages"
            :key="stage"
            class="flex flex-col"
          >
            <!-- Stage Header -->
            <div class="mb-3 flex items-center justify-between">
              <h3 class="font-semibold text-slate-900 dark:text-slate-25">
                {{ stage }}
              </h3>
              <button
                class="rounded-lg p-1 text-slate-600 hover:bg-slate-200 hover:text-slate-900 dark:text-slate-400 dark:hover:bg-slate-700 dark:hover:text-slate-100"
                @click="openNewTemplateModal(stage)"
              >
                <i class="i-lucide-plus h-4 w-4" />
              </button>
            </div>

            <!-- Templates List -->
            <div class="flex-1 space-y-3">
              <div
                v-for="template in getTemplatesForStage(stage)"
                :key="template.id"
                class="group relative rounded-lg border border-slate-200 bg-white p-4 dark:border-slate-700 dark:bg-slate-800"
              >
                <div class="mb-2 flex items-start justify-between">
                  <h4 class="font-medium text-slate-900 dark:text-slate-25">
                    {{ template.title }}
                  </h4>
                  <button
                    class="opacity-0 transition-opacity group-hover:opacity-100"
                    @click="openEditTemplateModal(template, stage)"
                  >
                    <i
                      class="i-lucide-pencil h-4 w-4 text-slate-600 dark:text-slate-400"
                    />
                  </button>
                </div>
                <p
                  class="mb-3 line-clamp-3 text-sm text-slate-600 dark:text-slate-400"
                >
                  {{ template.message }}
                </p>
                <div
                  class="flex items-center justify-between text-xs text-slate-500"
                >
                  <span>{{
                    template.created_at
                      ? new Date(template.created_at).toLocaleDateString()
                      : '-'
                  }}</span>
                  <button
                    class="text-red-600 hover:text-red-700 dark:text-red-400"
                    @click="handleDeleteTemplate(template, stage)"
                  >
                    {{ t('DELETE') }}
                  </button>
                </div>
              </div>

              <!-- Empty State -->
              <div
                v-if="getTemplatesForStage(stage).length === 0"
                class="flex flex-col items-center justify-center rounded-lg border border-dashed border-slate-300 bg-slate-50 p-8 dark:border-slate-600 dark:bg-slate-800"
              >
                <p
                  class="text-center text-sm text-slate-500 dark:text-slate-400"
                >
                  {{ t('KANBAN.TEMPLATES.NO_TEMPLATES') }}
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- No Funnels State -->
        <div
          v-else
          class="flex h-64 flex-col items-center justify-center rounded-lg border border-slate-200 bg-white dark:border-slate-700 dark:bg-slate-800"
        >
          <p class="mb-4 text-slate-600 dark:text-slate-400">
            {{ t('KANBAN.TEMPLATES.NO_FUNNELS') }}
          </p>
          <Button
            variant="primary"
            size="small"
            @click="$router.push({ name: 'kanban_settings' })"
          >
            {{ t('KANBAN.TEMPLATES.CREATE_FUNNEL') }}
          </Button>
        </div>
      </div>
    </div>

    <!-- Template Modal -->
    <KanbanTemplateModal
      v-if="showTemplateModal"
      :template="editingTemplate"
      :funnel-id="selectedFunnelId"
      :stage="selectedStage"
      :funnel="selectedFunnel"
      @close="closeTemplateModal"
      @saved="handleTemplateSaved"
    />
  </div>
</template>
