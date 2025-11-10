<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Modal from '../../../../components/Modal.vue';
import FunnelForm from './FunnelForm.vue';
import { default as FluentIcon } from 'shared/components/FluentIcon/Icon.vue';
import dashboardIcons from 'shared/components/FluentIcon/dashboard-icons.json';
import { useConfig } from 'dashboard/composables/useConfig';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const emit = defineEmits(['switch-view', 'back', 'funnel-created', 'save-funnel', 'discard-changes', 'create-new-funnel', 'create-from-template']);

const props = defineProps({
  editingFunnel: {
    type: Object,
    default: null,
  },
  funnelMetadata: {
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

const showNewFunnelModal = ref(false);
const showTemplatesModal = ref(false);
const selectedTemplate = ref(null);
const copiedId = ref(false);

const { isStacklab } = useConfig();

// Adicione um template vazio padrão
const emptyTemplate = {
  name: '',
  description: '',
  stages: {},
  settings: {
    agents: [],
  },
};

// Templates de funis pré-definidos
const funnelTemplates = [
  {
    id: 'sales',
    name: 'Funil de Vendas',
    icon: 'briefcase',
    description: 'Processo de vendas desde o primeiro contato até o fechamento',
    stages: {
      prospeccao: {
        name: 'Prospecção',
        color: '#6366f1',
        position: 1,
        description: 'Leads e primeiros contatos',
        message_templates: [
          {
            id: `template_${Date.now()}_1`,
            title: 'Boas vindas',
            content: 'Olá! Obrigado por entrar em contato. Como posso ajudar?',
            webhook: {
              url: '',
              method: 'POST',
              enabled: false,
            },
            stage_id: 'prospeccao',
            conditions: {
              rules: [],
              enabled: false,
            },
            created_at: new Date().toISOString(),
          },
        ],
      },
      qualificacao: {
        name: 'Qualificação',
        color: '#8b5cf6',
        position: 2,
        description: 'Análise de fit',
        message_templates: [
          {
            id: `template_${Date.now()}_2`,
            title: 'Agendamento de Reunião',
            content:
              'Podemos agendar uma reunião para entender melhor suas necessidades?',
            webhook: { url: '', method: 'POST', enabled: false },
            stage_id: 'qualificacao',
            conditions: { rules: [], enabled: false },
            created_at: new Date().toISOString(),
          },
        ],
      },
      proposta: {
        name: 'Proposta',
        color: '#ec4899',
        position: 3,
        description: 'Envio e negociação',
      },
      fechamento: {
        name: 'Fechamento',
        color: '#10b981',
        position: 4,
        description: 'Contratos e pagamentos',
      },
    },
  },
  {
    id: 'support',
    name: 'Funil de Suporte',
    icon: 'chat',
    description: 'Atendimento e resolução de tickets de suporte',
    stages: {
      novo: {
        name: 'Novo',
        color: '#6366f1',
        position: 1,
        description: 'Tickets recém abertos',
        message_templates: [
          {
            id: `template_${Date.now()}_3`,
            title: 'Confirmação de Recebimento',
            content: 'Recebemos seu ticket. Nossa equipe já está analisando.',
            webhook: { url: '', method: 'POST', enabled: false },
            stage_id: 'novo',
            conditions: { rules: [], enabled: false },
            created_at: new Date().toISOString(),
          },
        ],
      },
      analise: {
        name: 'Em Análise',
        color: '#8b5cf6',
        position: 2,
        description: 'Avaliação técnica',
        message_templates: [
          {
            id: `template_${Date.now()}_4`,
            title: 'Atualização de Status',
            content: 'Seu ticket está em análise pela nossa equipe técnica.',
            webhook: { url: '', method: 'POST', enabled: false },
            stage_id: 'analise',
            conditions: { rules: [], enabled: false },
            created_at: new Date().toISOString(),
          },
        ],
      },
      desenvolvimento: {
        name: 'Em Desenvolvimento',
        color: '#ec4899',
        position: 3,
        description: 'Correção em andamento',
      },
      teste: {
        name: 'Em Teste',
        color: '#f59e0b',
        position: 4,
        description: 'Validação da solução',
      },
      resolvido: {
        name: 'Resolvido',
        color: '#10b981',
        position: 5,
        description: 'Ticket finalizado',
      },
    },
  },
  {
    id: 'recruitment',
    name: 'Funil de Recrutamento',
    icon: 'people',
    description: 'Processo seletivo e contratação',
    stages: {
      triagem: {
        name: 'Triagem',
        color: '#6366f1',
        position: 1,
        description: 'Análise de currículos',
      },
      entrevista: {
        name: 'Entrevista',
        color: '#8b5cf6',
        position: 2,
        description: 'Conversa inicial',
      },
      teste: {
        name: 'Teste Técnico',
        color: '#ec4899',
        position: 3,
        description: 'Avaliação prática',
      },
      proposta: {
        name: 'Proposta',
        color: '#10b981',
        position: 4,
        description: 'Negociação final',
      },
    },
  },
];

const handleTemplateSelect = template => {
  console.log('Template selecionado:', template);

  // Formata o template igual ao formato de edição
  const formattedTemplate = {
    name: template.name,
    description: template.description,
    stages: Object.entries(template.stages).reduce(
      (acc, [id, stage]) => ({
        ...acc,
        [id]: {
          ...stage,
          id,
          message_templates: stage.message_templates || [], // Preserva os templates existentes
          position: stage.position, // Garante que a posição é mantida
        },
      }),
      {}
    ),
    settings: {
      agents: [],
    },
  };

  // Ordena as etapas por posição
  const orderedStages = {};
  Object.entries(formattedTemplate.stages)
    .sort(([, a], [, b]) => a.position - b.position)
    .forEach(([id, stage]) => {
      orderedStages[id] = stage;
    });

  formattedTemplate.stages = orderedStages;

  console.log('Template formatado:', formattedTemplate);

  // Envia para o pai abrir a view de criação com o template
  showTemplatesModal.value = false;
  emit('create-from-template', formattedTemplate);
};

const handleBack = () => {
  // Se estiver editando ou criando, emitir 'back' para voltar à lista de funis
  // Caso contrário, emitir 'switch-view' para voltar ao kanban
  if (props.editingFunnel || props.isCreating) {
    emit('back');
  } else {
    emit('switch-view', 'kanban');
  }
};

const handleFunnelCreated = funnel => {
  console.log('Funil criado:', funnel);
  showNewFunnelModal.value = false;
  emit('funnel-created', funnel);
};

const handleSaveFunnel = () => {
  emit('save-funnel');
};

const handleDiscardChanges = () => {
  emit('discard-changes');
};


const copyFunnelId = async () => {
  if (props.editingFunnel?.id) {
    await navigator.clipboard.writeText(props.editingFunnel.id.toString());
    copiedId.value = true;
    setTimeout(() => {
      copiedId.value = false;
    }, 2000);
  }
};
</script>

<template>
  <header class="funnels-header">
    <div class="flex items-center justify-between">
      <div class="flex items-center gap-4">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-chevron-left-icon lucide-chevron-left cursor-pointer text-slate-600 dark:text-slate-400" @click="handleBack">
          <path d="m15 18-6-6 6-6"/>
        </svg>
        <div class="flex items-center gap-4">
          <h1 class="text-base font-medium flex items-center gap-2">
            <span class="hidden md:inline">{{ editingFunnel ? 'Editando:' : isCreating ? 'Criando:' : t('KANBAN.FUNNELS.TITLE') }}</span>
            <span v-if="editingFunnel">{{ editingFunnel.name }}</span>
            <span v-if="isCreating">Novo Funil</span>
            <span v-if="editingFunnel" class="hidden md:flex px-2 py-1 text-xs bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 rounded flex items-center gap-2 cursor-pointer hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors" @click="copyFunnelId" title="Clique para copiar">
              <span class="text-[10px] text-slate-500 dark:text-slate-400 mr-1">ID:</span>{{ editingFunnel.id }}
              <svg v-if="!copiedId" xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-copy-icon lucide-copy">
                <rect width="14" height="14" x="8" y="8" rx="2" ry="2"/>
                <path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>
              </svg>
              <svg v-else xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-circle-check-big-icon lucide-circle-check-big">
                <path d="M21.801 10A10 10 0 1 1 17 3.335"/>
                <path d="m9 11 3 3L22 4"/>
              </svg>
              <span class="text-[10px] text-slate-500 dark:text-slate-400">{{ copiedId ? 'Copiado' : 'Copiar' }}</span>
            </span>
          </h1>
          <div v-if="editingFunnel && funnelMetadata.updated_at" class="hidden md:block text-xs text-slate-500 dark:text-slate-400">
            Atualizado em: {{ new Date(funnelMetadata.updated_at).toLocaleString() }}
          </div>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <!-- Botões quando NÃO está editando nem criando -->
        <template v-if="!editingFunnel && !isCreating">
          <Button
            v-if="isStacklab === true"
            variant="ghost"
            color="slate"
            size="sm"
            @click="showTemplatesModal = true"
          >
            <template #icon>
              <FluentIcon icon="copy" size="20" :icons="dashboardIcons" />
            </template>
            <span>Modelos</span>
          </Button>
          <Button
            variant="solid"
            color="blue"
            size="sm"
            @click="emit('create-new-funnel')"
          >
            <template #icon>
              <FluentIcon icon="add" size="20" :icons="dashboardIcons" />
            </template>
            <span>{{ t('KANBAN.FUNNELS.ACTIONS.NEW') }}</span>
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
              <span>Descartar</span>
            </Button>
          </div>
          <Button
            variant="solid"
            color="blue"
            size="sm"
            @click="handleSaveFunnel"
          >
            <span>Salvar</span>
          </Button>
        </template>
      </div>
    </div>

    <!-- Modal de Templates -->
    <Modal
      v-model:show="showTemplatesModal"
      :on-close="() => (showTemplatesModal = false)"
      size="medium"
    >
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4">
          {{ t('KANBAN.FUNNELS.TEMPLATES.TITLE') }}
        </h3>
        <div class="grid grid-cols-2 gap-4">
          <div
            v-for="template in funnelTemplates"
            :key="template.id"
            class="p-4 border rounded-lg hover:border-woot-500 cursor-pointer transition-colors"
            @click="handleTemplateSelect(template)"
          >
            <div class="flex items-center gap-2 mb-2">
              <fluent-icon
                :icon="template.icon"
                size="20"
                :icons="dashboardIcons"
                class="text-woot-500"
              />
              <h4 class="font-medium">{{ template.name }}</h4>
            </div>
            <p class="text-sm text-slate-600 dark:text-slate-400 mb-3">
              {{ template.description }}
            </p>
            <div class="flex flex-wrap gap-2">
              <span
                v-for="stage in Object.values(template.stages)"
                :key="stage.name"
                class="px-2 py-1 text-xs rounded-full"
                :style="{
                  backgroundColor: `${stage.color}20`,
                  color: stage.color,
                }"
              >
                {{ stage.name }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </Modal>

  </header>
</template>

<style lang="scss" scoped>
.funnels-header {
  padding: var(--space-normal);
  border-bottom: 1px solid var(--color-border);
  background: var(--white);
  margin-bottom: 16px;

  @apply dark:border-slate-800 dark:bg-slate-900;

  h1 {
    @apply dark:text-slate-100;
  }
}

:deep(.funnel-modal) {
  .modal-container {
    @apply max-w-[1024px] w-[90vw] dark:bg-slate-900;

    h3 {
      @apply dark:text-slate-100;
    }
  }
}

</style>
