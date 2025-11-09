<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, formatDistanceToNow } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import KanbanCustomFieldsTab from './KanbanCustomFieldsTab.vue';
import kanbanAPI from 'dashboard/api/kanban';

const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  conversationData: {
    type: Object,
    default: null,
  },
  loadingConversation: {
    type: Boolean,
    default: false,
  },
  currentStageName: {
    type: String,
    default: '',
  },
  itemDescription: {
    type: String,
    default: '',
  },
  isStacklab: {
    type: Boolean,
    default: false,
  },
  notes: {
    type: Array,
    default: () => [],
  },
  checklistItems: {
    type: Array,
    default: () => [],
  },
  attachments: {
    type: Array,
    default: () => [],
  },
});
const emit = defineEmits([
  'navigate-to-conversation',
  'context-menu',
  'stage-click',
  'update:item',
  'item-updated',
]);
const { t } = useI18n();
const store = useStore();

const contactGetter = useMapGetter('contacts/getContact');

// Computed para formatar data
const formatDate = date => {
  if (!date) return '';
  try {
    return format(new Date(date), 'dd/MM/yyyy HH:mm', { locale: ptBR });
  } catch (error) {
    console.error('Erro ao formatar data:', error);
    return '';
  }
};

// Computed para obter dados combinados da conversa (prioriza dados do item)
const conversationInfo = computed(() => {
  console.log('DEBUG - props.item:', props.item);
  console.log('DEBUG - props.conversationData:', props.conversationData);

  // Primeiro tenta usar os dados da conversa do item (preferência)
  const conversationData = props.item?.conversation;
  if (conversationData) {
    const result = {
      id: conversationData.id,
      display_id: conversationData.display_id,
      status: conversationData.status,
      last_activity_at: conversationData.last_activity_at,
      unread_count: conversationData.unread_count,
      label_list: conversationData.label_list || [],
      contact: conversationData.contact,
      inbox: conversationData.inbox,
      custom_attributes: conversationData.custom_attributes,
    };
    console.log('DEBUG - conversationInfo from item.conversation:', result);
    return result;
  }

  // Fallback para a prop conversationData (compatibilidade)
  if (props.conversationData) {
    console.log(
      'DEBUG - conversationInfo from props.conversationData:',
      props.conversationData
    );
    return props.conversationData;
  }

  console.log('DEBUG - conversationInfo: null');
  return null;
});

const contactId = computed(() => conversationInfo.value?.contact?.id);
const contact = computed(() => contactGetter.value(contactId.value));

const getContactDetails = () => {
  if (contactId.value) {
    store.dispatch('contacts/show', { id: contactId.value });
  }
};

// Watch para carregar dados do contato quando o contactId muda
watch(contactId, (newContactId, prevContactId) => {
  if (newContactId && newContactId !== prevContactId) {
    getContactDetails();
  }
});

// Watch para buscar counts quando o item muda
watch(
  () => props.item?.id,
  (newItemId, oldItemId) => {
    if (newItemId && newItemId !== oldItemId) {
      fetchItemCounts(newItemId);
    }
  },
  { immediate: false }
);

// Computed para obter os valores dos atributos do contato do store
const contactAttributeValues = computed(() => {
  console.log('DEBUG - contact from store:', contact.value);
  console.log(
    'DEBUG - contact custom_attributes:',
    contact.value?.custom_attributes
  );

  if (!contact.value?.custom_attributes) {
    console.log('DEBUG - No contact custom_attributes found');
    return [];
  }

  const attributes = Object.entries(contact.value.custom_attributes).map(
    ([key, value]) => ({
      key,
      value,
      displayName: key
        .replace(/_/g, ' ')
        .replace(/\b\w/g, l => l.toUpperCase()),
    })
  );

  console.log('DEBUG - contactAttributeValues:', attributes);
  return attributes;
});

// Computed para obter os valores dos atributos da conversa diretamente do objeto
const conversationAttributeValues = computed(() => {
  console.log(
    'DEBUG - conversation custom_attributes:',
    conversationInfo.value?.custom_attributes
  );

  if (!conversationInfo.value?.custom_attributes) {
    console.log('DEBUG - No conversation custom_attributes found');
    return [];
  }

  const attributes = Object.entries(
    conversationInfo.value.custom_attributes
  ).map(([key, value]) => ({
    key,
    value,
    displayName: key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()),
  }));

  console.log('DEBUG - conversationAttributeValues:', attributes);
  return attributes;
});

// Computed para obter os valores dos custom_attributes do item
const itemCustomAttributeValues = computed(() => {
  console.log(
    'DEBUG - item custom_attributes:',
    props.item?.item_details?.custom_attributes
  );

  if (!props.item?.item_details?.custom_attributes) {
    console.log('DEBUG - No item custom_attributes found');
    return [];
  }

  const attributes = Object.entries(
    props.item.item_details.custom_attributes
  ).map(([key, value]) => ({
    key,
    value,
    displayName: key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()),
    isArray: Array.isArray(value),
  }));

  console.log('DEBUG - itemCustomAttributeValues:', attributes);
  return attributes;
});

// Estado para controlar os accordions
const isItemInfoOpen = ref(false);
const isConversationOpen = ref(false);
const isCustomFieldsOpen = ref(false);

// Estado para controlar estatísticas
const statisticsCollapsed = ref(false);

// Estado para armazenar os counts do backend
const itemCounts = ref({
  notes_count: 0,
  checklist_count: 0,
  attachments_count: 0,
});

// Função para alternar estado das estatísticas
const toggleStatistics = () => {
  statisticsCollapsed.value = !statisticsCollapsed.value;
};

// Função para buscar os counts do item
const fetchItemCounts = async itemId => {
  try {
    const response = await kanbanAPI.getCounts(itemId);
    itemCounts.value = response.data;
  } catch (error) {
    console.error('Erro ao buscar counts do item:', error);
    // Fallback para valores calculados localmente
    itemCounts.value = {
      notes_count: props.notes?.length || 0,
      checklist_count: props.checklistItems?.length || 0,
      attachments_count: props.attachments?.length || 0,
    };
  }
};

// Computeds para estatísticas
const totalChecklistItems = computed(() => {
  if (!Array.isArray(props.checklistItems)) return 0;
  return props.checklistItems.length;
});

const completedChecklistItems = computed(() => {
  if (!Array.isArray(props.checklistItems)) return 0;
  return props.checklistItems.filter(item => item.completed).length;
});

const calculateStageChanges = activities => {
  if (!activities || !Array.isArray(activities)) return 0;
  return activities.filter(activity => activity.type === 'stage_changed')
    .length;
};

const stageChangesCount = computed(() => {
  return calculateStageChanges(props.item.activities);
});

const itemStatistics = computed(() => {
  const timeInStage = props.item.stage_entered_at
    ? formatDistanceToNow(new Date(props.item.stage_entered_at), {
        locale: ptBR,
        addSuffix: false,
      })
    : t('KANBAN.STATISTICS.NOT_AVAILABLE');

  // Usar os counts do backend, com fallback para valores calculados localmente
  const noteCount = itemCounts.value.notes_count;
  const checklistProgressText = `${completedChecklistItems.value}/${itemCounts.value.checklist_count}`;
  const attachmentCount = itemCounts.value.attachments_count;

  return [
    {
      icon: 'lock',
      label: t('KANBAN.STATISTICS.TIME_IN_STAGE'),
      value: timeInStage,
    },
    {
      icon: 'comment-add',
      label: t('KANBAN.STATISTICS.NOTES'),
      value: noteCount,
    },
    {
      icon: 'checkmark-circle',
      label: t('KANBAN.STATISTICS.CHECKLIST'),
      value: checklistProgressText,
    },
    {
      icon: 'attach',
      label: t('KANBAN.STATISTICS.ATTACHMENTS'),
      value: attachmentCount,
    },
    {
      icon: 'arrow-right',
      label: t('KANBAN.STATISTICS.STAGE_CHANGES'),
      value: stageChangesCount.value,
    },
  ];
});

// Carregar dados do contato quando o componente for montado
onMounted(() => {
  getContactDetails();
  // Buscar counts do item se ele existir
  if (props.item?.id) {
    fetchItemCounts(props.item.id);
  }
});
</script>

<template>
  <div class="w-full">
    <!-- Header do painel -->
    <div class="flex items-center p-4">
      <h2 class="text-lg font-semibold text-slate-900 dark:text-slate-100">
        {{ t('KANBAN.BASIC_DATA_PANEL.TITLE') || 'Dados Básicos' }}
      </h2>
    </div>

    <!-- Header do contato -->
    <div
      v-if="contact && conversationInfo"
      class="relative bg-gradient-to-r from-slate-50/80 to-slate-100/80 dark:from-slate-800/80 dark:to-slate-700/80 border border-slate-200/50 dark:border-slate-600/50 rounded-xl p-4 mx-2 mb-4 overflow-hidden shadow-sm hover:shadow-md transition-all duration-300"
    >
      <!-- Elemento decorativo de fundo -->
      <div
        class="absolute inset-0 bg-gradient-to-br from-blue-500/5 via-purple-500/5 to-pink-500/5 rounded-xl"
      />

      <!-- Conteúdo principal -->
      <div class="relative flex items-center gap-4">
        <!-- Avatar com efeitos modernos -->
        <div class="relative">
          <div
            class="absolute -inset-0.5 bg-gradient-to-r from-blue-500 to-purple-500 rounded-full blur opacity-30"
          />
          <div class="relative">
            <img
              v-if="contact.thumbnail"
              :src="contact.thumbnail"
              :alt="contact.name"
              class="w-12 h-12 rounded-full object-cover ring-2 ring-white dark:ring-slate-700 shadow-lg"
            />
            <div
              v-else
              class="w-12 h-12 bg-gradient-to-br from-slate-200 to-slate-300 dark:from-slate-600 dark:to-slate-500 rounded-full flex items-center justify-center ring-2 ring-white dark:ring-slate-700 shadow-lg"
            >
              <span
                class="text-sm font-bold text-slate-600 dark:text-slate-300"
              >
                {{ contact.name?.charAt(0)?.toUpperCase() || '?' }}
              </span>
            </div>
          </div>

          <!-- Indicador de status online/offline -->
          <div
            class="absolute -bottom-0.5 -right-0.5 w-4 h-4 rounded-full ring-2 ring-white dark:ring-slate-700 shadow-sm"
            :class="{
              'bg-green-400': contact.availability_status === 'online',
              'bg-yellow-400':
                contact.availability_status === 'busy' ||
                !contact.availability_status,
              'bg-slate-400': contact.availability_status === 'offline',
            }"
          >
            <div
              v-if="contact.availability_status === 'online'"
              class="w-full h-full rounded-full bg-green-400 animate-pulse"
            />
          </div>
        </div>

        <!-- Informações do contato -->
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-3 mb-1">
            <h3
              class="text-base font-bold text-slate-900 dark:text-slate-100 truncate"
            >
              {{ contact.name }}
            </h3>

            <!-- Status de disponibilidade com badge moderno -->
            <div class="flex items-center gap-1.5">
              <div
                class="flex items-center gap-1 px-2 py-1 rounded-full text-xs font-semibold shadow-sm"
                :class="{
                  'bg-green-100 text-green-700 dark:bg-green-900/50 dark:text-green-300 ring-1 ring-green-200 dark:ring-green-800':
                    contact.availability_status === 'online',
                  'bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300 ring-1 ring-yellow-200 dark:ring-yellow-800':
                    contact.availability_status === 'busy' ||
                    !contact.availability_status,
                  'bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300 ring-1 ring-slate-200 dark:ring-slate-600':
                    contact.availability_status === 'offline',
                }"
              >
                <div
                  class="w-1.5 h-1.5 rounded-full"
                  :class="{
                    'bg-green-500': contact.availability_status === 'online',
                    'bg-yellow-500':
                      contact.availability_status === 'busy' ||
                      !contact.availability_status,
                    'bg-slate-400': contact.availability_status === 'offline',
                  }"
                />
                <span class="capitalize">{{
                  contact.availability_status || 'ausente'
                }}</span>
              </div>
            </div>
          </div>

          <!-- Email e telefone com ícones -->
          <div
            class="flex items-center gap-4 text-xs text-slate-600 dark:text-slate-400 mb-2"
          >
            <a
              v-if="contact.email"
              :href="`mailto:${contact.email}`"
              class="flex items-center gap-1.5 hover:text-blue-600 dark:hover:text-blue-400 transition-colors group"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="group-hover:scale-110 transition-transform"
              >
                <path
                  d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"
                />
                <polyline points="22,6 12,13 2,6" />
              </svg>
              <span class="truncate max-w-32">{{ contact.email }}</span>
            </a>
            <a
              v-if="contact.phone_number"
              :href="`tel:${contact.phone_number}`"
              class="flex items-center gap-1.5 hover:text-green-600 dark:hover:text-green-400 transition-colors group"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="group-hover:scale-110 transition-transform"
              >
                <path
                  d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"
                />
              </svg>
              <span>{{ contact.phone_number }}</span>
            </a>
          </div>
        </div>

        <!-- Elementos decorativos sutis -->
        <div class="absolute top-2 right-2 flex gap-0.5">
          <div class="w-1 h-1 rounded-full bg-blue-400/40" />
          <div
            class="w-1 h-1 rounded-full bg-purple-400/40"
            style="animation-delay: 0.3s"
          />
          <div
            class="w-1 h-1 rounded-full bg-pink-400/40"
            style="animation-delay: 0.6s"
          />
        </div>
      </div>
    </div>

    <!-- Seção de Estatísticas -->
    <div class="item-statistics bg-white dark:bg-slate-800 rounded-lg p-3">
      <!-- Cabeçalho com botão de colapso -->
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2 text-base font-medium">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="lucide lucide-chart-no-axes-column-icon lucide-chart-no-axes-column"
          >
            <path d="M5 21v-6" />
            <path d="M12 21V3" />
            <path d="M19 21V9" />
          </svg>
          <span>{{ t('KANBAN.STATISTICS.TITLE') }}</span>
        </div>
        <button
          type="button"
          class="flex items-center justify-center w-8 h-8 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800"
          @click="toggleStatistics"
        >
          <fluent-icon
            :icon="statisticsCollapsed ? 'chevron-down' : 'chevron-up'"
            size="16"
          />
        </button>
      </div>

      <!-- Conteúdo colapsável -->
      <div
        v-show="!statisticsCollapsed"
        class="statistics-content transition-all duration-300 ease-in-out"
      >
        <div class="flex flex-col gap-2">
          <div
            v-for="stat in itemStatistics"
            :key="stat.label"
            class="flex items-center justify-between p-2 bg-slate-50 dark:bg-slate-700/50 rounded-md w-full"
          >
            <!-- Lado esquerdo: ícone + título -->
            <div class="flex items-center gap-1.5">
              <!-- Ícone inline para tempo na etapa -->
              <div v-if="stat.icon === 'lock'" class="flex-shrink-0">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  width="14"
                  height="14"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  class="lucide lucide-clock-icon lucide-clock text-slate-500 dark:text-slate-400"
                >
                  <path d="M12 6v6l4 2" />
                  <circle cx="12" cy="12" r="10" />
                </svg>
              </div>
              <!-- Outros ícones continuam usando fluent-icon -->
              <fluent-icon
                v-else
                :icon="stat.icon"
                size="14"
                class="text-slate-500 dark:text-slate-400"
              />
              <span class="text-xs text-slate-500 dark:text-slate-400">
                {{ stat.label }}
              </span>
            </div>

            <!-- Lado direito: valor -->
            <span
              class="text-sm font-medium text-slate-800 dark:text-slate-200"
            >
              {{ stat.value }}
            </span>
          </div>
        </div>
      </div>
    </div>

    <!-- Conteúdo do painel -->
    <div class="pb-8 list-group px-2">
      <div class="flex flex-col gap-3">
        <!-- Seção de Informações do Item -->
        <AccordionItem
          :title="
            t('KANBAN.BASIC_DATA_PANEL.ITEM_INFO') || 'Informações do Item'
          "
          :is-open="isItemInfoOpen"
          compact
          @toggle="isItemInfoOpen = !isItemInfoOpen"
        >
          <div class="p-2">
            <!-- Informações básicas do item -->
            <div class="mb-4">
              <div class="flex items-center justify-between mb-2">
                <h3
                  class="text-sm font-semibold text-slate-900 dark:text-slate-100"
                >
                  {{ item.title || item.name || 'Item' }}
                </h3>
                <span
                  class="text-xs px-2 py-1 bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-300 rounded"
                >
                  {{ currentStageName || 'Sem estágio' }}
                </span>
              </div>
              <p
                v-if="itemDescription"
                class="text-sm text-slate-600 dark:text-slate-400"
              >
                {{ itemDescription }}
              </p>
            </div>

            <!-- Atributos do Contato -->
            <div v-if="contactAttributeValues.length > 0" class="mb-4">
              <h4
                class="text-xs font-medium text-slate-700 dark:text-slate-300 uppercase tracking-wide mb-2"
              >
                Atributos do Contato
              </h4>
              <div class="space-y-2">
                <div
                  v-for="attr in contactAttributeValues"
                  :key="attr.key"
                  class="flex justify-between items-center py-2 px-3 bg-slate-50 dark:bg-slate-800 rounded border border-slate-200 dark:border-slate-700"
                >
                  <span
                    class="text-sm font-medium text-slate-700 dark:text-slate-300"
                  >
                    {{ attr.displayName }}
                  </span>
                  <span class="text-sm text-slate-900 dark:text-slate-100">
                    {{ attr.value }}
                  </span>
                </div>
              </div>
            </div>

            <!-- Atributos da Conversa -->
            <div v-if="conversationAttributeValues.length > 0" class="mb-4">
              <h4
                class="text-xs font-medium text-slate-700 dark:text-slate-300 uppercase tracking-wide mb-2"
              >
                Atributos da Conversa
              </h4>
              <div class="space-y-2">
                <div
                  v-for="attr in conversationAttributeValues"
                  :key="attr.key"
                  class="flex justify-between items-center py-2 px-3 bg-slate-50 dark:bg-slate-800 rounded border border-slate-200 dark:border-slate-700"
                >
                  <span
                    class="text-sm font-medium text-slate-700 dark:text-slate-300"
                  >
                    {{ attr.displayName }}
                  </span>
                  <span class="text-sm text-slate-900 dark:text-slate-100">
                    {{ attr.value }}
                  </span>
                </div>
              </div>
            </div>

            <!-- Atributos Customizados do Item -->
            <div v-if="itemCustomAttributeValues.length > 0" class="mb-4">
              <h4
                class="text-xs font-medium text-slate-700 dark:text-slate-300 uppercase tracking-wide mb-2"
              >
                Atributos do Item
              </h4>
              <div class="space-y-2">
                <div
                  v-for="attr in itemCustomAttributeValues"
                  :key="attr.key"
                  class="py-2 px-3 bg-slate-50 dark:bg-slate-800 rounded border border-slate-200 dark:border-slate-700"
                >
                  <div class="flex justify-between items-center mb-1">
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                    >
                      {{ attr.displayName }}
                    </span>
                  </div>
                  <!-- Se for array, mostra como lista -->
                  <div v-if="attr.isArray" class="mt-2">
                    <div class="flex flex-col gap-1">
                      <span
                        v-for="item in attr.value"
                        :key="item"
                        class="inline-flex items-center px-2 py-1 text-xs bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300 rounded-full w-fit"
                      >
                        {{ item }}
                      </span>
                    </div>
                  </div>
                  <!-- Se não for array, mostra como texto normal -->
                  <div
                    v-else
                    class="text-sm text-slate-900 dark:text-slate-100"
                  >
                    {{ attr.value }}
                  </div>
                </div>
              </div>
            </div>

            <!-- Mensagem quando não há atributos -->
            <div
              v-if="
                contactAttributeValues.length === 0 &&
                conversationAttributeValues.length === 0 &&
                itemCustomAttributeValues.length === 0
              "
              class="text-center py-4"
            >
              <span class="text-sm text-slate-500 dark:text-slate-400">
                {{ t('KANBAN.CUSTOM_FIELDS.NO_ATTRIBUTES_FOUND') }}
              </span>
            </div>
          </div>
        </AccordionItem>

        <!-- Seção de Conversa Vinculada -->
        <AccordionItem
          v-if="conversationInfo"
          :title="
            t('KANBAN.BASIC_DATA_PANEL.CONVERSATION') || 'Conversa Vinculada'
          "
          :is-open="isConversationOpen"
          compact
          @toggle="isConversationOpen = !isConversationOpen"
        >
          <div class="p-2">
            <div
              class="bg-white dark:bg-slate-800 rounded-lg border border-slate-200/30 dark:border-slate-700/30 p-3 cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-700/50 transition-colors"
              @click="
                $emit(
                  'navigate-to-conversation',
                  $event,
                  conversationInfo.display_id
                )
              "
              @contextmenu="$emit('context-menu', $event, conversationInfo.id)"
            >
              <!-- Contato -->
              <div
                v-if="conversationInfo.contact"
                class="flex items-center gap-3 mb-2"
              >
                <img
                  v-if="conversationInfo.contact.thumbnail"
                  :src="conversationInfo.contact.thumbnail"
                  :alt="conversationInfo.contact.name"
                  class="w-8 h-8 rounded-full object-cover"
                />
                <div
                  v-else
                  class="w-8 h-8 bg-slate-200 dark:bg-slate-600 rounded-full flex items-center justify-center"
                >
                  <span
                    class="text-xs font-medium text-slate-600 dark:text-slate-400"
                  >
                    {{
                      conversationInfo.contact.name?.charAt(0)?.toUpperCase() ||
                      '?'
                    }}
                  </span>
                </div>
                <div class="flex-1">
                  <div class="flex items-center justify-between">
                    <div
                      class="font-semibold text-sm text-slate-900 dark:text-slate-100"
                    >
                      <span
                        class="text-xs text-slate-500 dark:text-slate-400 mr-1"
                        >#{{ conversationInfo.display_id }}</span>
                      {{
                        conversationInfo.contact.name ||
                        t('KANBAN.CONTACT_UNKNOWN')
                      }}
                    </div>
                  </div>
                </div>
                <div class="flex items-center gap-1">
                  <!-- Status -->
                  <span
                    class="text-xs px-2 py-0.5 rounded-full font-medium"
                    :class="{
                      'bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300':
                        conversationInfo.status === 'open',
                      'bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300':
                        conversationInfo.status === 'pending',
                      'bg-slate-100 text-slate-700 dark:bg-slate-700 dark:text-slate-300':
                        conversationInfo.status === 'resolved',
                    }"
                  >
                    {{ conversationInfo.status }}
                  </span>
                  <!-- Unread count -->
                  <span
                    v-if="conversationInfo.unread_count > 0"
                    class="flex items-center justify-center h-5 min-w-[1rem] px-1.5 text-xs font-medium bg-red-500 text-white rounded-full shadow-sm"
                  >
                    {{
                      conversationInfo.unread_count > 9
                        ? '9+'
                        : conversationInfo.unread_count
                    }}
                  </span>
                </div>
              </div>

              <!-- Labels -->
              <div
                v-if="
                  conversationInfo.label_list &&
                  conversationInfo.label_list.length > 0
                "
                class="flex flex-wrap gap-1"
              >
                <span
                  v-for="label in conversationInfo.label_list"
                  :key="label"
                  class="text-xs px-2 py-0.5 bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300 rounded-full"
                >
                  {{ label }}
                </span>
              </div>
            </div>
          </div>
        </AccordionItem>

        <!-- Seção de Dados Adicionais -->
        <AccordionItem
          :title="t('KANBAN.CUSTOM_FIELDS.TITLE') || 'Dados Adicionais'"
          :is-open="isCustomFieldsOpen"
          compact
          @toggle="isCustomFieldsOpen = !isCustomFieldsOpen"
        >
          <div class="p-2">
            <KanbanCustomFieldsTab
              :item="item"
              :is-stacklab="isStacklab"
              @update:item="$emit('update:item', $event)"
              @item-updated="$emit('item-updated')"
            />
          </div>
        </AccordionItem>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
::v-deep {
  .contact--profile {
    @apply pb-3 border-b border-solid border-n-weak;
  }
}

/* Estilos para animação de colapso das estatísticas */
.item-statistics {
  /* Estilos já aplicados via classes Tailwind */
}

.statistics-content {
  overflow: hidden;
  transition: all 0.3s ease-in-out;
}

.statistics-content.collapsed {
  max-height: 0;
  opacity: 0;
  transform: translateY(-10px);
}

.statistics-content.expanded {
  max-height: 500px;
  opacity: 1;
  transform: translateY(0);
}
</style>
