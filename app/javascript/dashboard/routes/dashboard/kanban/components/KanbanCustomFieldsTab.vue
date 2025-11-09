<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { emitter } from 'shared/helpers/mitt';
import KanbanAPI from '../../../../api/kanban';

// Props
const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  isStacklab: {
    type: Boolean,
    default: false,
  },
});

// Emits
const emit = defineEmits(['update:item', 'item-updated']);

const { t } = useI18n();
const store = useStore();

// Computed para obter os funis
const funnels = computed(() => store.getters['funnel/getFunnels'] || []);

// Novo computed para merge de globais + customizados do item
const allCustomAttributes = computed(() => {
  // Busca o funil do item
  const funnel = funnels.value.find(
    f => String(f.id) === String(props.item?.funnel_id)
  );
  const globalAttrs = Array.isArray(funnel?.global_custom_attributes)
    ? funnel.global_custom_attributes
    : [];
  const itemAttrs = Array.isArray(props.item?.item_details?.custom_attributes)
    ? props.item?.item_details.custom_attributes
    : [];
  // Merge: para cada global, pega valor do item se existir
  const merged = globalAttrs.map(globalAttr => {
    const itemAttr = itemAttrs.find(
      a => a.name === globalAttr.name && a.type === globalAttr.type
    );
    return {
      name: globalAttr.name,
      type: globalAttr.type,
      is_list: globalAttr.is_list,
      list_values: globalAttr.list_values || [],
      value: itemAttr ? itemAttr.value : globalAttr.is_list ? [] : '',
      _isGlobal: true,
    };
  });
  // Adiciona os customizados do item que não são globais
  const onlyItemAttrs = itemAttrs.filter(
    attr => !globalAttrs.some(g => g.name === attr.name && g.type === attr.type)
  );
  return [...merged, ...onlyItemAttrs];
});

// Ref editável para os campos
const allCustomAttributesEditable = ref([]);

// Sincroniza ref editável ao trocar de item
watch(
  () => allCustomAttributes.value,
  newAttrs => {
    if (newAttrs && Array.isArray(newAttrs)) {
      allCustomAttributesEditable.value = newAttrs.map(attr => ({ ...attr }));
    } else {
      allCustomAttributesEditable.value = [];
    }
  },
  { immediate: true, deep: true }
);

// Função para atualizar o valor de um atributo
function updateAllCustomAttributeValue(idx, newValue) {
  allCustomAttributesEditable.value[idx].value = newValue;
}

// Estado para controlar dropdowns de lista
const openDropdownIndex = ref(null);

// Toggle dropdown de lista
const toggleListDropdown = idx => {
  openDropdownIndex.value = openDropdownIndex.value === idx ? null : idx;
};

// Adicionar/remover valor da lista
const toggleListValue = (idx, value) => {
  if (!Array.isArray(allCustomAttributesEditable.value[idx].value)) {
    allCustomAttributesEditable.value[idx].value = [];
  }

  const currentValues = allCustomAttributesEditable.value[idx].value;
  const valueIndex = currentValues.indexOf(value);

  if (valueIndex > -1) {
    // Remove se já existir
    currentValues.splice(valueIndex, 1);
  } else {
    // Adiciona se não existir
    currentValues.push(value);
  }

  updateAllCustomAttributeValue(idx, currentValues);
};

// Verificar se um valor está selecionado
const isValueSelected = (idx, value) => {
  const currentValues = allCustomAttributesEditable.value[idx]?.value;
  return Array.isArray(currentValues) && currentValues.includes(value);
};

// Fechar dropdown ao clicar fora
const closeDropdown = event => {
  const target = event.target;
  const isDropdownClick = target.closest('.custom-select-dropdown');

  if (!isDropdownClick) {
    openDropdownIndex.value = null;
  }
};

onMounted(() => {
  document.addEventListener('click', closeDropdown);
});

onUnmounted(() => {
  document.removeEventListener('click', closeDropdown);
});

// Função para salvar alterações
async function saveAllCustomAttributes() {
  try {
    // Salva todos como custom_attributes do item
    const attrs = allCustomAttributesEditable.value.map(attr => ({
      name: attr.name,
      type: attr.type,
      value: attr.value,
    }));
    const payload = {
      ...props.item,
      custom_attributes: attrs,
      item_details: {
        ...props.item?.item_details,
        custom_attributes: attrs,
      },
    };
    const { data } = await KanbanAPI.updateItem(props.item?.id, payload);
    emit('update:item', data);
    emit('item-updated');

    // Mostrar mensagem de sucesso
    emitter.emit('newToastMessage', {
      message: 'Campos personalizados salvos com sucesso',
      action: { type: 'success' },
    });
  } catch (error) {
    console.error('Erro ao salvar campos personalizados:', error);
    emitter.emit('newToastMessage', {
      message: 'Erro ao salvar campos personalizados',
      action: { type: 'error' },
    });
  }
}
</script>

<template>
  <div class="space-y-4">
    <template v-if="allCustomAttributesEditable.length === 0">
      <p class="text-sm text-slate-500">
        Nenhum campo personalizado disponível.
      </p>
    </template>
    <div
      v-for="(attr, idx) in allCustomAttributesEditable"
      :key="attr.name + '-' + attr.type"
      class="flex flex-col gap-2"
    >
      <label
        class="font-medium flex items-center gap-1 text-sm text-slate-700 dark:text-slate-300"
      >
        <fluent-icon
          v-if="attr._isGlobal"
          icon="globe"
          size="14"
          class="text-woot-500 align-middle flex-shrink-0"
          title="Campo global do funil"
        />
        <span>{{ attr.name }}</span>
      </label>
      <!-- Select customizado para campos do tipo lista -->
      <div v-if="attr.is_list" class="custom-select-dropdown relative">
        <!-- Botão do select -->
        <button
          type="button"
          class="w-full input flex items-center justify-between"
          @click="toggleListDropdown(idx)"
        >
          <span
            v-if="!Array.isArray(attr.value) || attr.value.length === 0"
            class="text-slate-400 text-sm"
          >
            Selecione...
          </span>
          <span v-else class="text-sm">
            {{ attr.value.length }} selecionado{{
              attr.value.length !== 1 ? 's' : ''
            }}
          </span>
          <fluent-icon
            icon="chevron-down"
            size="16"
            :class="{ 'rotate-180': openDropdownIndex === idx }"
            class="transition-transform"
          />
        </button>

        <!-- Dropdown menu -->
        <div
          v-if="openDropdownIndex === idx"
          class="absolute top-full left-0 w-full mt-1 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-lg z-10 max-h-60 overflow-y-auto"
        >
          <div
            v-for="option in attr.list_values"
            :key="option"
            class="flex items-center px-3 py-2 hover:bg-slate-50 dark:hover:bg-slate-700 cursor-pointer"
            @click="toggleListValue(idx, option)"
          >
            <div
              class="w-4 h-4 rounded border mr-2 flex items-center justify-center"
              :class="
                isValueSelected(idx, option)
                  ? 'bg-woot-500 border-woot-500'
                  : 'border-slate-300 dark:border-slate-600'
              "
            >
              <fluent-icon
                v-if="isValueSelected(idx, option)"
                icon="checkmark"
                size="12"
                class="text-white"
              />
            </div>
            <span class="text-sm">{{ option }}</span>
          </div>
        </div>

        <!-- Badges dos valores selecionados -->
        <div
          v-if="Array.isArray(attr.value) && attr.value.length > 0"
          class="flex flex-wrap gap-1 mt-2"
        >
          <span
            v-for="val in attr.value"
            :key="val"
            class="inline-flex items-center px-2 py-1 text-xs bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300 rounded-full"
          >
            {{ val }}
          </span>
        </div>
      </div>
      <!-- Inputs para outros tipos -->
      <input
        v-else-if="attr.type === 'string'"
        v-model="attr.value"
        type="text"
        class="w-full input"
        @change="updateAllCustomAttributeValue(idx, attr.value)"
      />
      <input
        v-else-if="attr.type === 'number'"
        v-model.number="attr.value"
        type="number"
        class="w-full input"
        @change="updateAllCustomAttributeValue(idx, attr.value)"
      />
      <input
        v-else-if="attr.type === 'date'"
        v-model="attr.value"
        type="date"
        class="w-full input"
        @change="updateAllCustomAttributeValue(idx, attr.value)"
      />
      <input
        v-else
        v-model="attr.value"
        type="text"
        class="w-full input"
        @change="updateAllCustomAttributeValue(idx, attr.value)"
      />
    </div>
    <button class="primary-button mt-4" @click="saveAllCustomAttributes">
      Salvar
    </button>
  </div>
</template>

<style scoped>
.input {
  @apply px-3 py-2 text-sm border border-slate-200 bg-slate-50 rounded-lg focus:ring-1 focus:ring-woot-500 focus:border-woot-500 dark:bg-slate-800 dark:border-slate-700 dark:text-slate-300;
}

.primary-button {
  @apply px-4 py-2 text-sm font-medium text-white
         bg-woot-500 hover:bg-woot-600
         dark:bg-woot-600 dark:hover:bg-woot-700
         rounded-lg transition-colors;

  &:disabled {
    @apply opacity-50 cursor-not-allowed;
  }
}

.custom-select-dropdown {
  position: relative;
}

.rotate-180 {
  transform: rotate(180deg);
}
</style>
