# Kanban - Funcionalidades Faltantes

## Visão Geral

Após análise do vídeo "Kanban para Chatwoot 4.1" e descrição da funcionalidade de IA, identificamos as seguintes funcionalidades que **NÃO** foram implementadas na versão inicial do frontend custom.

## Funcionalidades Faltantes

### 1. Filtros Universais de Ganhos/Perdidos

**Prioridade**: ALTA
**Complexidade**: BAIXA

**Descrição**:
Adicionar dois botões de toggle no header do Kanban Board para filtrar universalmente itens marcados como "ganho" ou "perdido".

**Localização no vídeo**: 00:04:11 - 00:04:47

**Comportamento**:
- Dois botões ao lado do botão "New Item" no header
- **Ativo**: Botão azul → mostra apenas itens com esse status
- **Inativo**: Botão cinza → não filtra
- Os filtros são independentes (pode ativar/desativar separadamente)

**Implementação Necessária**:

#### Frontend:
```vue
<!-- KanbanBoard.vue - Header -->
<div class="flex items-center gap-2">
  <!-- Filtro Ganhos -->
  <button
    @click="toggleWonFilter"
    :class="[
      'rounded-md px-3 py-2 text-sm font-medium',
      wonFilterActive
        ? 'bg-green-600 text-white'
        : 'bg-slate-200 text-slate-600 dark:bg-slate-700 dark:text-slate-400'
    ]"
  >
    {{ t('KANBAN.FILTER.WON') }}
  </button>

  <!-- Filtro Perdidos -->
  <button
    @click="toggleLostFilter"
    :class="[
      'rounded-md px-3 py-2 text-sm font-medium',
      lostFilterActive
        ? 'bg-red-600 text-white'
        : 'bg-slate-200 text-slate-600 dark:bg-slate-700 dark:text-slate-400'
    ]"
  >
    {{ t('KANBAN.FILTER.LOST') }}
  </button>
</div>
```

#### Vuex Store:
```javascript
// Adicionar ao state
filters: {
  showWon: false,
  showLost: false,
}

// Adicionar getter
getFilteredItems: ($state, getters) => {
  let items = Object.values($state.records);

  if ($state.filters.showWon) {
    items = items.filter(item => item.item_details?.status === 'won');
  }

  if ($state.filters.showLost) {
    items = items.filter(item => item.item_details?.status === 'lost');
  }

  return items;
}

// Adicionar action
toggleWonFilter({ commit, state }) {
  commit('setFilter', { showWon: !state.filters.showWon });
}
```

**Backend**:
- ✅ Já suporta via `item_details.status`
- Nenhuma mudança necessária

---

### 2. Mensagem Padrão/Rápida Automática

**Prioridade**: ALTA
**Complexidade**: MÉDIA

**Descrição**:
Permitir configurar um modelo de mensagem que é enviado automaticamente quando um item entra em uma etapa específica.

**Localização no vídeo**: 00:01:43 - 00:03:47

**Comportamento**:
1. Na gestão de modelos de mensagem, adicionar toggle "Mensagem Padrão" para cada etapa
2. Quando item é movido para a etapa com mensagem padrão ativa, enviar automaticamente
3. Toggle no header da coluna (azul = ativo, cinza = inativo) para ativar/desativar temporariamente

**Implementação Necessária**:

#### 1. Configuração de Template (Settings ou Modal)
```vue
<!-- Adicionar em KanbanSettings.vue ou criar TemplateMessageSettings.vue -->
<div class="space-y-4">
  <h3>{{ t('KANBAN.TEMPLATE_MESSAGES.TITLE') }}</h3>

  <!-- Para cada etapa do funil -->
  <div v-for="stage in selectedFunnel.stages" :key="stage">
    <label>{{ stage }}</label>

    <!-- Toggle Mensagem Padrão -->
    <div class="flex items-center gap-2">
      <input
        type="checkbox"
        v-model="templateConfig[stage].enabled"
      />
      <span>{{ t('KANBAN.TEMPLATE_MESSAGES.DEFAULT_MESSAGE') }}</span>
    </div>

    <!-- Editor de mensagem -->
    <textarea
      v-model="templateConfig[stage].message"
      :placeholder="t('KANBAN.TEMPLATE_MESSAGES.MESSAGE_PLACEHOLDER')"
      class="w-full"
    />

    <!-- Variáveis disponíveis -->
    <div class="text-sm text-slate-500">
      {{ t('KANBAN.TEMPLATE_MESSAGES.AVAILABLE_VARS') }}:
      <code>{{item_title}}</code>, <code>{{agent_name}}</code>, etc.
    </div>
  </div>
</div>
```

#### 2. Toggle na Coluna
```vue
<!-- KanbanColumn.vue - Header -->
<div class="flex items-center gap-2">
  <button
    v-if="hasTemplateMessage"
    @click="toggleTemplateMessage"
    :class="[
      'rounded-md p-1',
      templateMessageActive
        ? 'bg-blue-600 text-white'
        : 'bg-slate-200 text-slate-600'
    ]"
    :title="t('KANBAN.TEMPLATE_MESSAGES.TOGGLE')"
  >
    <i class="i-lucide-mail" />
  </button>
</div>
```

#### 3. Lógica de Envio ao Mover
```javascript
// Em KanbanColumn.vue - handleDragEnd
const handleDragEnd = async (event) => {
  if (event.added) {
    const item = event.added.element;

    // Mover item
    await store.dispatch('kanban/move', {
      id: item.id,
      funnel_stage: props.stage,
      position: event.added.newIndex,
    });

    // Verificar se deve enviar mensagem padrão
    if (templateMessageActive.value && hasTemplateMessage.value) {
      await store.dispatch('kanban/sendTemplateMessage', {
        itemId: item.id,
        stage: props.stage,
      });
    }
  }
};
```

#### Backend:
- ✅ Já tem `KanbanTemplateMessageHandler` concern
- ✅ Endpoint provavelmente existe (verificar `schedule_message`)
- Pode precisar endpoint específico: `POST /kanban_items/:id/send_template_message`

---

### 3. Drag Bar (Opções Rápidas ao Arrastar)

**Prioridade**: MÉDIA
**Complexidade**: MÉDIA

**Descrição**:
Quando usuário arrasta um item, mostrar 3 botões de ação rápida na parte inferior: Mover, Abrir Chat, Duplicar.

**Localização no vídeo**: 00:04:52 - 00:05:32

**Comportamento**:
- Aparecem ao iniciar drag
- Somem ao soltar item
- 3 opções:
  1. **Mover Item** - comportamento padrão (move e fecha opções)
  2. **Abrir Chat** - abre conversa vinculada em nova aba/modal
  3. **Duplicar Item** - duplica o card (adiciona sufixo "drag")

**Implementação Necessária**:

#### Vue Component - DragBar
```vue
<!-- components/KanbanDragBar.vue -->
<script setup>
import { ref } from 'vue';

const props = defineProps({
  visible: Boolean,
  item: Object,
});

const emit = defineEmits(['move', 'open-chat', 'duplicate']);
</script>

<template>
  <Transition name="slide-up">
    <div
      v-if="visible"
      class="fixed bottom-0 left-0 right-0 z-50 flex items-center justify-center gap-4 bg-slate-900/95 p-4 backdrop-blur-sm"
    >
      <!-- Mover Item -->
      <button
        @click="emit('move')"
        class="flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-2 text-white hover:bg-blue-700"
      >
        <i class="i-lucide-move" />
        <span>{{ t('KANBAN.DRAG_BAR.MOVE') }}</span>
      </button>

      <!-- Abrir Chat -->
      <button
        @click="emit('open-chat')"
        class="flex items-center gap-2 rounded-lg bg-green-600 px-4 py-2 text-white hover:bg-green-700"
      >
        <i class="i-lucide-message-circle" />
        <span>{{ t('KANBAN.DRAG_BAR.OPEN_CHAT') }}</span>
      </button>

      <!-- Duplicar -->
      <button
        @click="emit('duplicate')"
        class="flex items-center gap-2 rounded-lg bg-purple-600 px-4 py-2 text-white hover:bg-purple-700"
      >
        <i class="i-lucide-copy" />
        <span>{{ t('KANBAN.DRAG_BAR.DUPLICATE') }}</span>
      </button>
    </div>
  </Transition>
</template>

<style scoped>
.slide-up-enter-active,
.slide-up-leave-active {
  transition: transform 0.3s ease;
}

.slide-up-enter-from,
.slide-up-leave-to {
  transform: translateY(100%);
}
</style>
```

#### Integração com KanbanColumn
```vue
<!-- KanbanColumn.vue -->
<script setup>
import { ref } from 'vue';
import KanbanDragBar from './KanbanDragBar.vue';

const draggingItem = ref(null);
const showDragBar = ref(false);

const handleDragStart = (event) => {
  draggingItem.value = event.item._underlying_vm_;
  showDragBar.value = true;
};

const handleDragEnd = () => {
  showDragBar.value = false;
  draggingItem.value = null;
};

const handleMove = () => {
  // Comportamento padrão - já implementado
  showDragBar.value = false;
};

const handleOpenChat = () => {
  if (draggingItem.value?.conversation_display_id) {
    // Abrir conversa
    const accountId = store.getters.getCurrentAccountId;
    window.open(`/app/accounts/${accountId}/conversations/${draggingItem.value.conversation_display_id}`, '_blank');
  }
  showDragBar.value = false;
};

const handleDuplicate = async () => {
  await store.dispatch('kanban/duplicate', draggingItem.value.id);
  showDragBar.value = false;
};
</script>

<template>
  <draggable
    v-model="items"
    @start="handleDragStart"
    @end="handleDragEnd"
    ...
  >
    <!-- ... -->
  </draggable>

  <KanbanDragBar
    :visible="showDragBar"
    :item="draggingItem"
    @move="handleMove"
    @open-chat="handleOpenChat"
    @duplicate="handleDuplicate"
  />
</template>
```

#### Backend:
- ✅ Duplicate já existe: `POST /kanban_items/:id/duplicate`

---

### 4. Status Visual Melhorado

**Prioridade**: BAIXA
**Complexidade**: BAIXA

**Descrição**:
Melhorar visualização do status (ganho/perdido/aberto) com card visual no topo do modal de detalhes.

**Localização no vídeo**: 00:05:36 - 00:06:07

**Implementação Necessária**:

```vue
<!-- KanbanItemModal.vue - No topo do modal -->
<div
  v-if="item"
  :class="[
    'mb-4 flex items-center gap-2 rounded-lg p-3',
    statusColor
  ]"
>
  <component :is="statusIcon" class="h-6 w-6" />
  <span class="font-semibold">{{ statusText }}</span>
</div>

<script setup>
const statusColor = computed(() => {
  const status = formData.value.status;
  return {
    won: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
    lost: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
    open: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
  }[status] || 'bg-slate-100 text-slate-800';
});

const statusIcon = computed(() => {
  const status = formData.value.status;
  const icons = {
    won: 'i-lucide-check-circle',
    lost: 'i-lucide-x-circle',
    open: 'i-lucide-circle-dashed',
  };
  return icons[status] || icons.open;
});
</script>
```

---

### 5. Geração de Itens por IA (OpenAI)

**Prioridade**: ALTA (Feature Principal)
**Complexidade**: ALTA

**Descrição**:
Integração com OpenAI para gerar itens automaticamente a partir de contatos ou conversas.

**Funcionalidades**:
1. Configurar chave OpenAI em Settings → Integrations → OpenAI
2. Opção para IA sugerir etiquetas/labels
3. Botões "Otimizar Fluxo" e "Gerar Itens" no Kanban Board
4. Seletor de funil
5. Escolher fonte: Contatos ou Conversas
6. Gerar até 10 itens por vez
7. IA preenche automaticamente:
   - Título
   - Descrição/resumo da conversa
   - Prioridade (baseada no histórico)
   - Agente atribuído
   - Vínculo com conversa
   - Status

**Implementação Necessária**:

#### 1. Configuração OpenAI (Settings)
```vue
<!-- app/javascript/dashboard/routes/dashboard/settings/integrations/OpenAI.vue -->
<template>
  <div class="space-y-6">
    <h2>{{ t('SETTINGS.INTEGRATIONS.OPENAI.TITLE') }}</h2>

    <!-- API Key -->
    <div>
      <label>{{ t('SETTINGS.INTEGRATIONS.OPENAI.API_KEY') }}</label>
      <input
        v-model="apiKey"
        type="password"
        placeholder="sk-..."
        class="w-full"
      />
    </div>

    <!-- Sugerir Labels -->
    <div class="flex items-center gap-2">
      <input
        type="checkbox"
        v-model="suggestLabels"
      />
      <span>{{ t('SETTINGS.INTEGRATIONS.OPENAI.SUGGEST_LABELS') }}</span>
    </div>

    <button @click="saveConfig">
      {{ t('SAVE') }}
    </button>
  </div>
</template>
```

#### 2. Modal de Geração de Itens
```vue
<!-- components/KanbanAIGenerateModal.vue -->
<template>
  <Modal :show="true" @close="$emit('close')">
    <div class="space-y-6">
      <h2>{{ t('KANBAN.AI.GENERATE_ITEMS') }}</h2>

      <!-- Selecionar Funil -->
      <div>
        <label>{{ t('KANBAN.AI.SELECT_FUNNEL') }}</label>
        <select v-model="selectedFunnelId">
          <option v-for="funnel in funnels" :key="funnel.id" :value="funnel.id">
            {{ funnel.name }}
          </option>
        </select>
      </div>

      <!-- Fonte de Dados -->
      <div>
        <label>{{ t('KANBAN.AI.DATA_SOURCE') }}</label>
        <div class="flex gap-4">
          <label class="flex items-center gap-2">
            <input type="radio" v-model="dataSource" value="contacts" />
            {{ t('KANBAN.AI.FROM_CONTACTS') }}
          </label>
          <label class="flex items-center gap-2">
            <input type="radio" v-model="dataSource" value="conversations" />
            {{ t('KANBAN.AI.FROM_CONVERSATIONS') }}
          </label>
        </div>
      </div>

      <!-- Quantidade -->
      <div>
        <label>{{ t('KANBAN.AI.ITEM_COUNT') }}</label>
        <input
          type="number"
          v-model.number="itemCount"
          min="1"
          max="10"
        />
        <p class="text-sm text-slate-500">
          {{ t('KANBAN.AI.MAX_10_ITEMS') }}
        </p>
      </div>

      <!-- Botões -->
      <div class="flex justify-end gap-2">
        <Button variant="clear" @click="$emit('close')">
          {{ t('CANCEL') }}
        </Button>
        <Button
          variant="primary"
          :is-loading="generating"
          @click="generateItems"
        >
          {{ t('KANBAN.AI.GENERATE') }}
        </Button>
      </div>
    </div>
  </Modal>
</template>

<script setup>
const generateItems = async () => {
  generating.value = true;

  try {
    const response = await store.dispatch('kanban/generateItemsWithAI', {
      funnelId: selectedFunnelId.value,
      dataSource: dataSource.value,
      count: itemCount.value,
    });

    useAlert(t('KANBAN.AI.ITEMS_GENERATED', { count: response.data.length }));
    emit('close');
  } catch (error) {
    useAlert(t('KANBAN.AI.ERROR_GENERATING'), 'error');
  } finally {
    generating.value = false;
  }
};
</script>
```

#### 3. Botões no KanbanBoard
```vue
<!-- KanbanBoard.vue - Header -->
<div class="flex items-center gap-2">
  <!-- Otimizar Fluxo -->
  <Button
    variant="smooth"
    size="small"
    @click="showOptimizeFlowModal = true"
  >
    <i class="i-lucide-sparkles" />
    {{ t('KANBAN.AI.OPTIMIZE_FLOW') }}
  </Button>

  <!-- Gerar Itens -->
  <Button
    variant="smooth"
    size="small"
    @click="showGenerateModal = true"
  >
    <i class="i-lucide-wand-2" />
    {{ t('KANBAN.AI.GENERATE_ITEMS') }}
  </Button>
</div>
```

#### Backend Necessário:
```ruby
# app/controllers/api/v1/accounts/kanban_items_controller.rb

def generate_with_ai
  # Parâmetros: funnel_id, data_source (contacts/conversations), count
  # Chamar serviço de IA para gerar itens

  result = KanbanAIGeneratorService.new(
    account: current_account,
    funnel_id: params[:funnel_id],
    data_source: params[:data_source],
    count: params[:count] || 10
  ).call

  render json: result[:items]
end

# app/services/kanban_ai_generator_service.rb
class KanbanAIGeneratorService
  def initialize(account:, funnel_id:, data_source:, count:)
    @account = account
    @funnel_id = funnel_id
    @data_source = data_source
    @count = [count.to_i, 10].min # Max 10
  end

  def call
    conversations = fetch_conversations
    items = []

    conversations.first(@count).each do |conversation|
      # Gerar resumo com OpenAI
      summary = generate_summary(conversation)

      # Criar item
      item = KanbanItem.create!(
        account: @account,
        funnel_id: @funnel_id,
        funnel_stage: funnel.stages.first, # Primeira etapa
        conversation_display_id: conversation.display_id,
        item_details: {
          title: summary[:title],
          description: summary[:description],
          priority: summary[:priority],
          status: 'open'
        },
        assigned_agents: [conversation.assignee&.id].compact
      )

      items << item
    end

    { items: items }
  end

  private

  def generate_summary(conversation)
    # Integração com OpenAI
    client = OpenAI::Client.new(access_token: @account.openai_api_key)

    messages = conversation.messages.last(10).map(&:content).join("\n")

    response = client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          {
            role: "system",
            content: "Você é um assistente que analisa conversas e gera resumos para um sistema CRM Kanban. Retorne JSON com: title, description, priority (low/medium/high/urgent)"
          },
          {
            role: "user",
            content: "Analise esta conversa e gere um resumo:\n\n#{messages}"
          }
        ],
        response_format: { type: "json_object" }
      }
    )

    JSON.parse(response.dig("choices", 0, "message", "content")).symbolize_keys
  end
end
```

---

## Priorização de Implementação

### Fase 1 (Alta Prioridade - 1-2 dias)
1. ✅ Filtros Universais Ganhos/Perdidos
2. ✅ Mensagem Padrão/Rápida Automática
3. ✅ Status Visual Melhorado

### Fase 2 (Média Prioridade - 1 dia)
4. ✅ Drag Bar (Opções Rápidas)

### Fase 3 (Alta Prioridade - 3-5 dias)
5. ✅ Geração de Itens por IA (OpenAI)

## Traduções Necessárias

```json
// en/kanban.json
{
  "KANBAN": {
    "FILTER": {
      "WON": "Won",
      "LOST": "Lost"
    },
    "TEMPLATE_MESSAGES": {
      "TITLE": "Template Messages",
      "DEFAULT_MESSAGE": "Default Message",
      "MESSAGE_PLACEHOLDER": "Enter template message...",
      "AVAILABLE_VARS": "Available variables",
      "TOGGLE": "Toggle auto-send"
    },
    "DRAG_BAR": {
      "MOVE": "Move Item",
      "OPEN_CHAT": "Open Chat",
      "DUPLICATE": "Duplicate"
    },
    "AI": {
      "OPTIMIZE_FLOW": "Optimize Flow",
      "GENERATE_ITEMS": "Generate Items",
      "SELECT_FUNNEL": "Select Funnel",
      "DATA_SOURCE": "Data Source",
      "FROM_CONTACTS": "From Contacts",
      "FROM_CONVERSATIONS": "From Conversations",
      "ITEM_COUNT": "Number of Items",
      "MAX_10_ITEMS": "Maximum 10 items per generation",
      "GENERATE": "Generate",
      "ITEMS_GENERATED": "{count} items generated successfully",
      "ERROR_GENERATING": "Error generating items"
    }
  }
}
```

## Conclusão

A implementação inicial cobriu ~60% das funcionalidades do Kanban real. As funcionalidades mais críticas faltantes são:

1. **Geração de Itens por IA** (feature principal de diferenciação)
2. **Mensagem Padrão Automática** (muito solicitada)
3. **Filtros Ganhos/Perdidos** (usabilidade)

Recomendo implementar na ordem de priorização acima para entregar valor incremental.
