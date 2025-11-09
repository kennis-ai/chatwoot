<script setup>
import { ref, watch, computed, provide, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import KanbanTab from './components/KanbanTab.vue';
import ListTab from './components/ListTab.vue';
import AgendaTab from './components/AgendaTab.vue';
import FunnelsManager from './components/FunnelsManager.vue';
import OffersManager from './components/OffersManager.vue';
import MessageTemplates from './components/MessageTemplates.vue';

import KanbanItemDetailView from './components/KanbanItemDetailView.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const currentView = ref('kanban');
const selectedItemId = ref(null);
const forceReloadCounter = ref(0);
const hasLicenseError = ref(false);
const licenseErrorDetails = ref(null);

const selectedFunnel = computed(
  () => store.getters['funnel/getSelectedFunnel']
);
const labelsMap = ref({});
const isPageReady = ref(false);

provide('labelsMap', labelsMap);

// Watch para carregar itens quando um funil for selecionado
watch(selectedFunnel, async (newFunnel, oldFunnel) => {
  if (newFunnel?.id && newFunnel.id !== oldFunnel?.id) {
    try {
      // Carregar itens de todas as etapas do funil selecionado em paralelo
      const stageIds = Object.keys(newFunnel.stages || {});

      // Carregar itens de todas as etapas em paralelo para melhor performance
      const promises = stageIds.map(stageId =>
        store.dispatch('kanban/fetchKanbanItems', { stageId })
      );

      await Promise.all(promises);

      hasLicenseError.value = false;
      licenseErrorDetails.value = null;
    } catch (error) {
      if (
        error.response?.status === 403 ||
        error.status === 403 ||
        error.response?.data?.code === 'STACKLAB_TOKEN_NOT_FOUND'
      ) {
        hasLicenseError.value = true;
        licenseErrorDetails.value = error.response?.data || error.data || error;
      }
    }
  }
});

// Watch para mudanças na rota
watch(
  () => route.query,
  async (newQuery, oldQuery) => {
    // Determinar a view baseada na prioridade: item-detail > funnels > offers > view param > kanban
    if (newQuery.item) {
      const itemId = parseInt(newQuery.item);
      if (
        itemId !== selectedItemId.value ||
        currentView.value !== 'item-detail'
      ) {
        selectedItemId.value = itemId;
        forceReloadCounter.value += 1;
        currentView.value = 'item-detail';
      }
    } else if (newQuery.funnel) {
      const funnelId = newQuery.funnel;
      const funnels = store.getters['funnel/getFunnels'];
      const funnel = funnels.find(f => String(f.id) === String(funnelId));
      if (funnel && funnel.id !== selectedFunnel.value?.id) {
        try {
          await store.dispatch('funnel/setSelectedFunnel', funnel);
        } catch (error) {
          if (
            error.response?.status === 403 ||
            error.status === 403 ||
            error.response?.data?.code === 'STACKLAB_TOKEN_NOT_FOUND'
          ) {
            hasLicenseError.value = true;
            licenseErrorDetails.value =
              error.response?.data || error.data || error;
          }
        }
      }
      // Mudar para view de funnels quando há parâmetro funnel na URL
      currentView.value = 'funnels';
      selectedItemId.value = null;
    } else if (newQuery.offer) {
      // Mudar para view de offers quando há parâmetro offer na URL
      currentView.value = 'offers';
      selectedItemId.value = null;
    } else {
      // Verificar se estamos saindo da edição de um funil (removendo o parâmetro funnel)
      const wasEditingFunnel =
        oldQuery.funnel && !newQuery.funnel && currentView.value === 'funnels';
      // Verificar se estamos saindo da edição de uma oferta (removendo o parâmetro offer)
      const wasEditingOffer =
        oldQuery.offer && !newQuery.offer && currentView.value === 'offers';

      if (wasEditingFunnel) {
        // Se estávamos editando um funil e removemos o parâmetro, manter na view de funnels
        selectedItemId.value = null;
        return;
      }

      if (wasEditingOffer) {
        // Se estávamos editando uma oferta e removemos o parâmetro, manter na view de offers
        selectedItemId.value = null;
        return;
      }

      // Quando não há item, funnel ou offer específico na URL, usar o parâmetro view ou voltar para kanban
      const newView = newQuery.view || 'kanban';
      if (newView !== currentView.value) {
        currentView.value = newView;
      }
      // Quando não há item na URL, voltar para kanban se estiver na view de detalhe
      if (currentView.value === 'item-detail') {
        currentView.value = newView;
      }
      selectedItemId.value = null;
    }
  },
  { immediate: true, deep: true }
);

// Carregar funis ao montar o componente
onMounted(async () => {
  try {
    await store.dispatch('funnel/fetch');
    isPageReady.value = true;
  } catch (error) {
    if (
      error.response?.status === 403 ||
      error.status === 403 ||
      error.response?.data?.code === 'STACKLAB_TOKEN_NOT_FOUND'
    ) {
      hasLicenseError.value = true;
      licenseErrorDetails.value = error.response?.data || error.data || error;
    }
  }
});

const createMode = ref(false);

const switchView = (view, options = {}) => {
  currentView.value = view;
  selectedItemId.value = null;

  // Atualizar URL para manter a view no refresh
  const currentQuery = { ...route.query };

  if (view === 'kanban') {
    // Remover parâmetro view quando volta para kanban
    delete currentQuery.view;
    delete currentQuery.offer;
    delete currentQuery.funnel;
    delete currentQuery.item;
  } else if (view === 'offers') {
    // Para offers, adicionar view=offers mas manter offer se existir
    currentQuery.view = 'offers';
  } else if (view === 'funnels') {
    // Para funnels, adicionar view=funnels mas manter funnel se existir
    currentQuery.view = 'funnels';
  } else if (view !== 'item-detail') {
    // Para outras views, adicionar o parâmetro view
    currentQuery.view = view;
  }

  // Atualizar URL sem recarregar a página
  router.replace({ query: currentQuery });

  // Se estiver navegando para funnels com mode 'create', ativar modo de criação
  if (view === 'funnels' && options.mode === 'create') {
    createMode.value = true;
  } else {
    createMode.value = false;
  }
};
const handleItemClick = item => {
  selectedItemId.value = item.id;
  forceReloadCounter.value += 1;
  currentView.value = 'item-detail';
};
const handleBackFromDetail = () => {
  currentView.value = 'kanban';
  selectedItemId.value = null;
};

const getCurrentComponent = computed(() => {
  switch (currentView.value) {
    case 'kanban':
      return KanbanTab;
    case 'list':
      return ListTab;
    case 'agenda':
      return AgendaTab;
    case 'funnels':
      return FunnelsManager;
    case 'offers':
      return OffersManager;
    case 'templates':
      return MessageTemplates;

    case 'item-detail':
      return KanbanItemDetailView;
    default:
      return KanbanTab;
  }
});
</script>

<template>
  <div class="flex h-full w-full overflow-hidden">
    <!-- Mensagem de erro de licenciamento -->
    <div
      v-if="hasLicenseError"
      class="w-full h-full bg-slate-50 dark:bg-slate-900 flex items-center justify-center"
    >
      <div class="text-center max-w-md mx-auto p-6">
        <div class="text-red-500 text-6xl mb-4">🔒</div>
        <h2
          class="text-xl font-semibold text-slate-800 dark:text-slate-200 mb-2"
        >
          Licença Necessária
        </h2>
        <p class="text-slate-600 dark:text-slate-400">
          Esta instalação não possui uma licença válida para acessar o Kanban.
          Entre em contato com o administrador da plataforma.
        </p>
      </div>
    </div>

    <!-- Conteúdo real quando estiver pronto -->
    <component
      :is="getCurrentComponent"
      :key="currentView + (createMode ? '-create' : '')"
      :current-view="currentView"
      :labels-map="labelsMap"
      :item-id="selectedItemId"
      :force-reload="forceReloadCounter"
      :create-mode="createMode"
      @switch-view="switchView"
      @item-click="handleItemClick"
      @back="handleBackFromDetail"
    />
  </div>
</template>

<style scoped>
.flex {
  min-height: 0;
  min-width: 0;
  height: 100%;
  width: 100%;
}
</style>
