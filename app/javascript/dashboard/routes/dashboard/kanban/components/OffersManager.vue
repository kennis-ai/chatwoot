<script setup>
import { ref, onMounted, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useConfig } from 'dashboard/composables/useConfig';
import Modal from '../../../../components/Modal.vue';
import { emitter } from 'shared/helpers/mitt';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import OffersHeader from './OffersHeader.vue';
import offersAPI from '../../../../api/offers';

// Prop para detectar modo de criação
const props = defineProps({
  createMode: {
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
const router = useRouter();
const { isStacklab } = useConfig();
const loading = ref(false);
const offers = ref([]);
const isLimitReached = ref(false);

// Estado para os modais
const showDeleteModal = ref(false);
const offerToDelete = ref(null);

// Estado para edição inline
const isEditingMode = ref(false);
const offerBeingEdited = ref(null);

// Estado para criação de nova oferta
const isCreatingMode = ref(false);

// Estado para gerenciar a imagem
const selectedImage = ref(null);
const imagePreview = ref(null);

// Watcher para detectar quando deve iniciar o modo de criação
watch(
  () => props.createMode,
  newValue => {
    if (newValue) {
      startCreate();
    }
  }
);

// Função para mapear dados da API para o formato esperado pelo componente
const mapOfferFromAPI = offer => ({
  id: offer.id,
  name: offer.title,
  discount_percentage: offer.value,
  currency: offer.currency,
  type: offer.type,
  created_at: offer.created_at,
  image_url: offer.image_url,
});

// Função para mapear dados do componente para a API
const mapOfferToAPI = offer => ({
  title: offer.name,
  value: offer.discount_percentage,
  currency: offer.currency,
  type: offer.type,
});

const refreshOfferData = async () => {
  loading.value = true;
  try {
    const response = await offersAPI.getOffers();
    offers.value = (response.data || []).map(mapOfferFromAPI);
    isLimitReached.value = !isStacklab && offers.value.length >= 10;
  } catch (error) {
    console.error('Erro ao carregar ofertas:', error);
    emitter.emit('newToastMessage', {
      message: t('KANBAN.OFFERS.MANAGER.ERROR_LOAD_DATA'),
      action: { type: 'error' },
    });
  } finally {
    loading.value = false;
  }
};

const confirmDelete = offer => {
  offerToDelete.value = offer;
  showDeleteModal.value = true;
};

const handleDelete = async () => {
  try {
    loading.value = true;
    await offersAPI.deleteOffer(offerToDelete.value.id);

    // Remover da lista local
    offers.value = offers.value.filter(o => o.id !== offerToDelete.value.id);

    emitter.emit('newToastMessage', {
      message: t('KANBAN.OFFERS.MANAGER.SUCCESS_DELETED'),
      action: { type: 'success' },
    });

    showDeleteModal.value = false;
    offerToDelete.value = null;
  } catch (error) {
    console.error('Erro ao excluir oferta:', error);
    emitter.emit('newToastMessage', {
      message: t('KANBAN.OFFERS.MANAGER.ERROR_DELETE'),
      action: { type: 'error' },
    });
  } finally {
    loading.value = false;
  }
};

const startEdit = offer => {
  offerBeingEdited.value = { ...offer };
  isEditingMode.value = true;
  isCreatingMode.value = false;
  selectedImage.value = null;
  imagePreview.value = offer.image_url || null;

  // Adicionar parâmetro 'offer' na URL
  const currentQuery = { ...router.currentRoute.value.query };
  currentQuery.offer = offer.id;
  router.replace({ query: currentQuery });
};

const startCreate = () => {
  offerBeingEdited.value = {
    name: '',
    discount_percentage: 0,
    currency: 'BRL',
    type: 'product',
  };
  isEditingMode.value = false;
  isCreatingMode.value = true;
  selectedImage.value = null;
  imagePreview.value = null;

  // Remover parâmetro 'offer' da URL quando criando nova oferta
  const currentQuery = { ...router.currentRoute.value.query };
  delete currentQuery.offer;
  router.replace({ query: currentQuery });
};

const handleEdit = async updatedOffer => {
  try {
    loading.value = true;

    let offerData;

    // Se há uma imagem selecionada, usar FormData
    if (selectedImage.value) {
      offerData = new FormData();
      offerData.append('offer[title]', updatedOffer.name);
      offerData.append('offer[value]', updatedOffer.discount_percentage);
      offerData.append('offer[currency]', updatedOffer.currency);
      offerData.append('offer[type]', updatedOffer.type);
      offerData.append('offer[image]', selectedImage.value);
    } else {
      offerData = mapOfferToAPI(updatedOffer);
    }

    let response;
    if (isCreatingMode.value) {
      response = await offersAPI.createOffer(offerData);
      // Adicionar na lista local (já mapeado)
      offers.value.push(mapOfferFromAPI(response.data));
    } else {
      response = await offersAPI.updateOffer(updatedOffer.id, offerData);
      // Atualizar na lista local
      const index = offers.value.findIndex(o => o.id === updatedOffer.id);
      if (index !== -1) {
        offers.value[index] = mapOfferFromAPI(response.data);
      }
    }

    const message = isCreatingMode.value
      ? t('KANBAN.OFFERS.MANAGER.SUCCESS_CREATED')
      : t('KANBAN.OFFERS.MANAGER.SUCCESS_UPDATED');
    emitter.emit('newToastMessage', {
      message,
      action: { type: 'success' },
    });

    isEditingMode.value = false;
    isCreatingMode.value = false;
    offerBeingEdited.value = null;
    selectedImage.value = null;
    imagePreview.value = null;

    // Remover parâmetro 'offer' da URL quando sair do modo de edição/criação
    const currentQuery = { ...router.currentRoute.value.query };
    delete currentQuery.offer;
    router.replace({ query: currentQuery });
  } catch (error) {
    console.error('Erro ao salvar oferta:', error);
    const message = isCreatingMode.value
      ? t('KANBAN.OFFERS.MANAGER.ERROR_CREATE')
      : t('KANBAN.OFFERS.MANAGER.ERROR_UPDATE');
    emitter.emit('newToastMessage', {
      message,
      action: { type: 'error' },
    });
  } finally {
    loading.value = false;
  }
};

const duplicateOffer = async offer => {
  try {
    loading.value = true;

    const duplicatedData = mapOfferToAPI({
      ...offer,
      name: `${offer.name} (cópia)`,
    });

    const response = await offersAPI.createOffer(duplicatedData);
    offers.value.push(mapOfferFromAPI(response.data));

    emitter.emit('newToastMessage', {
      message: t('KANBAN.OFFERS.MANAGER.SUCCESS_DUPLICATED'),
      action: { type: 'success' },
    });
  } catch (error) {
    console.error('Erro ao duplicar oferta:', error);
    emitter.emit('newToastMessage', {
      message: t('KANBAN.OFFERS.MANAGER.ERROR_DUPLICATE'),
      action: { type: 'error' },
    });
  } finally {
    loading.value = false;
  }
};

// Handlers para o OffersHeader
const handleBack = () => {
  emit('back');
};

const handleSaveOffer = () => {
  // Salvar a oferta atual sendo editada ou criada
  if (isEditingMode.value || isCreatingMode.value) {
    handleEdit(offerBeingEdited.value);
  }
};

const handleDiscardChanges = () => {
  isEditingMode.value = false;
  isCreatingMode.value = false;
  offerBeingEdited.value = null;
  selectedImage.value = null;
  imagePreview.value = null;

  // Remover parâmetro 'offer' da URL
  const currentQuery = { ...router.currentRoute.value.query };
  delete currentQuery.offer;
  router.replace({ query: currentQuery });
};

const handleImageSelect = event => {
  const file = event.target.files[0];
  if (file && file.type.startsWith('image/')) {
    selectedImage.value = file;

    // Criar preview da imagem
    const reader = new FileReader();
    reader.onload = e => {
      imagePreview.value = e.target.result;
    };
    reader.readAsDataURL(file);
  }
};

const handleCreateNewOffer = () => {
  startCreate();
};

onMounted(async () => {
  await refreshOfferData();

  // Verificar se há parâmetro 'offer' na URL para abrir em modo de edição
  const currentQuery = router.currentRoute.value.query;
  if (currentQuery.offer) {
    const offerId = parseInt(currentQuery.offer);
    const offer = offers.value.find(o => o.id === offerId);
    if (offer) {
      startEdit(offer);
    }
  }
});
</script>

<template>
  <div class="flex flex-col h-full bg-white dark:bg-slate-900 p-4">
    <!-- Offers Header -->
    <OffersHeader
      :editing-offer="offerBeingEdited"
      :offer-metadata="
        offerBeingEdited
          ? {
              updated_at: offerBeingEdited.created_at,
              name: offerBeingEdited.name,
            }
          : {}
      "
      :is-creating="isCreatingMode"
      @switch-view="emit('switch-view', $event)"
      @back="handleBack"
      @offer-created="emit('offer-created', $event)"
      @save-offer="handleSaveOffer"
      @discard-changes="handleDiscardChanges"
      @create-new-offer="handleCreateNewOffer"
    />

    <div class="offers-content flex-1 overflow-y-auto">
      <!-- Renderiza formulário quando estiver editando ou criando -->
      <div
        v-if="(isEditingMode || isCreatingMode) && offerBeingEdited"
        class="mb-6"
      >
        <div
          class="bg-white dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700 p-6"
        >
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-medium">
              {{
                isCreatingMode
                  ? t('KANBAN.OFFERS.MANAGER.CREATE_NEW_OFFER')
                  : t('KANBAN.OFFERS.MANAGER.EDIT_OFFER')
              }}
            </h3>
            <Button
              variant="ghost"
              color="slate"
              size="sm"
              @click="
                isEditingMode = false;
                isCreatingMode = false;
                offerBeingEdited = null;
              "
            >
              <template #icon>
                <fluent-icon icon="dismiss" size="16" />
              </template>
              {{ t('KANBAN.OFFERS.MANAGER.CANCEL') }}
            </Button>
          </div>

          <!-- Formulário simples de oferta -->
          <div class="space-y-4">
            <div>
              <label class="block text-sm font-medium mb-1">{{
                t('KANBAN.OFFERS.MANAGER.TITLE_LABEL')
              }}</label>
              <input
                v-model="offerBeingEdited.name"
                type="text"
                class="w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700"
                :placeholder="t('KANBAN.OFFERS.MANAGER.TITLE_PLACEHOLDER')"
                required
              />
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">{{
                t('KANBAN.OFFERS.MANAGER.TYPE_LABEL')
              }}</label>
              <select
                v-model="offerBeingEdited.type"
                class="w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700"
                required
              >
                <option value="product">
                  {{ t('KANBAN.OFFERS.MANAGER.TYPE_PRODUCT') }}
                </option>
                <option value="service">
                  {{ t('KANBAN.OFFERS.MANAGER.TYPE_SERVICE') }}
                </option>
              </select>
            </div>

            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium mb-1">{{
                  t('KANBAN.OFFERS.MANAGER.VALUE_LABEL')
                }}</label>
                <input
                  v-model.number="offerBeingEdited.discount_percentage"
                  type="number"
                  min="0.01"
                  step="0.01"
                  class="w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700"
                  placeholder="0.00"
                  required
                />
              </div>

              <div>
                <label class="block text-sm font-medium mb-1">{{
                  t('KANBAN.OFFERS.MANAGER.CURRENCY_LABEL')
                }}</label>
                <select
                  v-model="offerBeingEdited.currency"
                  class="w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700"
                  required
                >
                  <option value="BRL">
                    {{ t('KANBAN.OFFERS.MANAGER.CURRENCY_BRL') }}
                  </option>
                  <option value="USD">
                    {{ t('KANBAN.OFFERS.MANAGER.CURRENCY_USD') }}
                  </option>
                  <option value="EUR">
                    {{ t('KANBAN.OFFERS.MANAGER.CURRENCY_EUR') }}
                  </option>
                  <option value="GBP">
                    {{ t('KANBAN.OFFERS.MANAGER.CURRENCY_GBP') }}
                  </option>
                </select>
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">{{
                t('KANBAN.OFFERS.MANAGER.IMAGE_LABEL')
              }}</label>
              <div class="flex items-center gap-4">
                <input
                  type="file"
                  accept="image/png, image/jpeg, image/jpg, image/gif, image/webp"
                  class="w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700"
                  @change="handleImageSelect"
                />
              </div>
              <div v-if="imagePreview" class="mt-3">
                <img
                  :src="imagePreview"
                  alt="Preview"
                  class="max-w-xs max-h-48 rounded-lg border border-slate-200 dark:border-slate-700"
                />
              </div>
            </div>

            <div class="flex justify-end gap-2">
              <Button
                variant="ghost"
                color="slate"
                @click="
                  isEditingMode = false;
                  isCreatingMode = false;
                  offerBeingEdited = null;
                "
              >
                {{ t('KANBAN.OFFERS.MANAGER.CANCEL') }}
              </Button>
              <Button
                variant="solid"
                color="blue"
                :is-loading="loading"
                @click="handleEdit(offerBeingEdited)"
              >
                {{
                  isCreatingMode
                    ? t('KANBAN.OFFERS.MANAGER.CREATE_BUTTON')
                    : t('KANBAN.OFFERS.MANAGER.SAVE_CHANGES')
                }}
              </Button>
            </div>
          </div>
        </div>
      </div>

      <!-- Renderiza lista de ofertas quando NÃO estiver editando -->
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
                {{ t('KANBAN.OFFERS.MANAGER.LIMIT_REACHED_TITLE') }}
              </p>
              <p class="text-amber-700 dark:text-amber-200 text-sm mt-1">
                {{ t('KANBAN.OFFERS.MANAGER.LIMIT_REACHED_MESSAGE') }}
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
          v-else-if="!offers.length"
          class="flex flex-col items-center justify-center py-12 text-slate-600"
        >
          <fluent-icon icon="task" size="48" class="mb-4 text-slate-400" />
          <p class="text-lg">
            {{ t('KANBAN.OFFERS.MANAGER.EMPTY_STATE_TITLE') }}
          </p>
          <p class="text-sm">
            {{ t('KANBAN.OFFERS.MANAGER.EMPTY_STATE_MESSAGE') }}
          </p>
        </div>

        <!-- Offers List -->
        <div
          v-else
          class="grid gap-6 grid-cols-1 md:grid-cols-2 lg:grid-cols-3"
        >
          <div
            v-for="offer in offers"
            :key="offer.id"
            class="offer-card bg-white dark:bg-slate-800 rounded-xl shadow-sm border border-slate-200/50 dark:border-slate-700/50 overflow-hidden relative"
          >
            <!-- Imagem da oferta -->
            <div v-if="offer.image_url" class="w-full h-40">
              <img
                :src="offer.image_url"
                :alt="offer.name"
                class="w-full h-full object-cover"
              />
            </div>
            <!-- Placeholder quando não há imagem -->
            <div
              v-else
              class="w-full h-40 bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-800 dark:to-slate-900 flex items-center justify-center"
            >
              <fluent-icon
                icon="image"
                size="56"
                class="text-slate-300 dark:text-slate-700"
              />
            </div>

            <!-- Conteúdo do card -->
            <div class="p-5">
              <!-- Informações básicas -->
              <div class="mb-4">
                <div class="flex items-center gap-2 mb-2">
                  <span
                    class="inline-block px-2 py-0.5 text-xs font-medium text-slate-500 dark:text-slate-400 bg-slate-100 dark:bg-slate-700 rounded"
                  >
                    #{{ offer.id }}
                  </span>
                  <span
                    class="inline-block px-2 py-0.5 text-xs font-medium rounded"
                    :class="[
                      offer.type === 'service'
                        ? 'bg-blue-100 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300'
                        : 'bg-purple-100 dark:bg-purple-900/20 text-purple-700 dark:text-purple-300',
                    ]"
                  >
                    {{
                      offer.type === 'service'
                        ? t('KANBAN.OFFERS.MANAGER.TYPE_SERVICE')
                        : t('KANBAN.OFFERS.MANAGER.TYPE_PRODUCT')
                    }}
                  </span>
                </div>
                <h3
                  class="text-lg font-semibold text-slate-900 dark:text-white"
                >
                  {{ offer.name }}
                </h3>
              </div>

              <!-- Valor e moeda -->
              <div class="mb-4">
                <div
                  class="inline-flex items-center gap-2 px-3 py-1.5 bg-green-50 dark:bg-green-900/20 rounded-lg"
                >
                  <fluent-icon
                    icon="tag"
                    size="16"
                    class="text-green-600 dark:text-green-400"
                  />
                  <span
                    class="text-base font-bold text-green-700 dark:text-green-300"
                  >
                    {{ offer.discount_percentage }} {{ offer.currency }}
                  </span>
                </div>
              </div>

              <!-- Rodapé com data e ações -->
              <div
                class="flex items-center justify-between pt-3 border-t border-slate-100 dark:border-slate-700"
              >
                <p class="text-xs text-slate-500 dark:text-slate-400">
                  {{ new Date(offer.created_at).toLocaleDateString() }}
                </p>

                <!-- Botões de Ação -->
                <div class="flex items-center gap-1">
                  <Button
                    variant="ghost"
                    color="slate"
                    size="sm"
                    @click="startEdit(offer)"
                  >
                    <template #icon>
                      <fluent-icon icon="edit" size="16" />
                    </template>
                  </Button>
                  <Button
                    variant="ghost"
                    color="slate"
                    size="sm"
                    @click="duplicateOffer(offer)"
                  >
                    <template #icon>
                      <fluent-icon icon="copy" size="16" />
                    </template>
                  </Button>
                  <Button
                    variant="ghost"
                    color="ruby"
                    size="sm"
                    @click="confirmDelete(offer)"
                  >
                    <template #icon>
                      <fluent-icon icon="delete" size="16" />
                    </template>
                  </Button>
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
          {{ t('KANBAN.OFFERS.MANAGER.DELETE_MODAL_TITLE') }}
        </h3>
        <p class="text-sm text-slate-600 mb-6">
          {{ t('KANBAN.OFFERS.MANAGER.DELETE_MODAL_MESSAGE') }} "{{
            offerToDelete?.name
          }}"?
          {{ t('KANBAN.OFFERS.MANAGER.DELETE_MODAL_WARNING') }}
        </p>
        <div class="flex justify-end gap-2">
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            @click="showDeleteModal = false"
          >
            {{ t('KANBAN.OFFERS.MANAGER.CANCEL') }}
          </Button>
          <Button
            variant="solid"
            color="ruby"
            size="sm"
            :is-loading="loading"
            @click="handleDelete"
          >
            {{ t('KANBAN.OFFERS.MANAGER.DELETE_BUTTON') }}
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

.offers-content {
  min-height: 0; // Importante para o scroll funcionar
}
</style>
