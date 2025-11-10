<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50 backdrop-blur-[4px]">
    <div class="relative bg-white dark:bg-slate-900 rounded-2xl shadow-2xl w-full max-w-[110rem] p-8 overflow-y-auto max-h-[90vh] scrollbar-hidden">
      <!-- Botão de fechar -->
      <button @click="onClose" class="absolute top-4 right-4 text-slate-400 hover:text-slate-700 dark:hover:text-slate-200 text-2xl font-bold focus:outline-none">×</button>
      <!-- Header -->
      <div class="flex items-center gap-4 mb-6">
        <div :style="{ backgroundColor: color }" class="w-8 h-8 rounded-lg" />
        <div>
          <h2 class="text-2xl font-bold text-slate-900 dark:text-slate-100">{{ title }}</h2>
          <p v-if="description" class="text-slate-500 dark:text-slate-400 text-sm mt-1">{{ description }}</p>
        </div>
      </div>
      <!-- Métricas em texto -->
      <div class="mb-6 text-slate-700 dark:text-slate-200 text-[15px] flex flex-col sm:flex-row flex-wrap gap-y-2 gap-x-4 items-start sm:items-center leading-tight">
        <span><span class="font-bold text-slate-900 dark:text-slate-100">{{ items.length }}</span> cards</span>
        <span class="mx-2 hidden sm:inline">•</span>
        <span>Valor total: <span class="font-bold text-green-700 dark:text-green-400">{{ formattedTotal }}</span></span>
        <span class="mx-2 hidden sm:inline">•</span>
        <span>Valor médio: <span class="font-semibold text-slate-800 dark:text-slate-200">{{ formattedAvg }}</span></span>
        <span class="mx-2 hidden sm:inline">•</span>
        <span>Máx: <span class="font-semibold text-slate-800 dark:text-slate-200">{{ formattedMax }}</span></span>
        <span class="mx-2 hidden sm:inline">•</span>
        <span>Mín: <span class="font-semibold text-slate-800 dark:text-slate-200">{{ formattedMin }}</span></span>
        <span class="mx-2 hidden sm:inline">•</span>
        <span class="inline-flex items-center gap-1"><span class="w-2 h-2 rounded-full bg-slate-400 inline-block"></span><span class="text-xs">Aberto:</span> <span class="font-semibold">{{ statusList[0].count }}</span></span>
        <span class="mx-2 hidden sm:inline">•</span>
        <span class="inline-flex items-center gap-1"><span class="w-2 h-2 rounded-full bg-green-600 inline-block"></span><span class="text-xs">Ganho:</span> <span class="font-semibold">{{ statusList[1].count }}</span></span>
        <span class="mx-2 hidden sm:inline">•</span>
        <span class="inline-flex items-center gap-1"><span class="w-2 h-2 rounded-full bg-red-600 inline-block"></span><span class="text-xs">Perdido:</span> <span class="font-semibold">{{ statusList[2].count }}</span></span>
      </div>
      <!-- Fim do bloco de métricas em texto -->
      <!-- Cards de status -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-3 mb-4 min-w-[600px]">
        <div class="metric-card-glass metric-gradient-slate card-block">
          <div class="metric-label-glass">Abertos</div>
          <div class="metric-value-glass">{{ statusList[0].count }}</div>
        </div>
        <div class="metric-card-glass metric-gradient-success card-block">
          <div class="metric-label-glass">Ganho</div>
          <div class="metric-value-glass">{{ statusList[1].count }}</div>
        </div>
        <div class="metric-card-glass metric-gradient-danger card-block">
          <div class="metric-label-glass">Perdido</div>
          <div class="metric-value-glass">{{ statusList[2].count }}</div>
        </div>
      </div>
      <!-- Principais agentes e Prioridades lado a lado -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-2 mb-2">
        <div class="card-block card-header-agentes">
          <div class="card-block-header card-block-header-agentes">Principais agentes</div>
          <div class="flex flex-wrap gap-2">
            <div v-for="agent in topAgents" :key="agent.id" class="flex items-center gap-1 border border-slate-200 dark:border-slate-700 rounded-full px-2 py-1 bg-transparent text-xs text-slate-600 dark:text-slate-300">
              <Avatar :name="agent.name" :src="agent.avatar_url" :size="24" />
              <span class="truncate max-w-[80px]">{{ agent.name }}</span>
              <span class="opacity-60">({{ agent.count }})</span>
            </div>
            <div v-if="extraAgents > 0" class="flex items-center gap-1 border border-slate-200 dark:border-slate-700 rounded-full px-2 py-1 text-xs font-semibold text-slate-500 dark:text-slate-400 bg-transparent">
              +{{ extraAgents }} outros
            </div>
          </div>
        </div>
        <div class="card-block card-header-prioridades">
          <div class="card-block-header card-block-header-prioridades">Prioridades</div>
          <div class="flex gap-2 flex-wrap">
            <div v-for="prio in priorities" :key="prio.key" class="flex items-center gap-1 border border-slate-200 dark:border-slate-700 rounded-full px-2 py-1 bg-transparent text-xs text-slate-600 dark:text-slate-300">
              <span :class="prio.class + ' w-2 h-2 rounded-full inline-block'" />
              <span>{{ prio.label }}</span>
              <span class="opacity-60">({{ prio.count }})</span>
            </div>
          </div>
        </div>
      </div>
      <!-- Status e Cards sem agente lado a lado -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-1 mb-2">
        <div class="card-block card-header-status">
          <div class="card-block-header card-block-header-status">Status</div>
          <div class="flex gap-2 flex-wrap">
            <div v-for="stat in statusList" :key="stat.key" class="flex items-center gap-1 border border-slate-200 dark:border-slate-700 rounded-full px-2 py-1 bg-transparent text-xs text-slate-600 dark:text-slate-300">
              <span :class="stat.class + ' w-2 h-2 rounded-full inline-block'" />
              <span>{{ stat.label }}</span>
              <span class="opacity-60">({{ stat.count }})</span>
            </div>
          </div>
        </div>
        <div class="card-block card-header-sem-agente">
          <div class="card-block-header card-block-header-sem-agente">Cards sem agente</div>
          <div class="flex gap-2 flex-wrap">
            <div class="flex items-center gap-1 border border-slate-200 dark:border-slate-700 rounded-full px-2 py-1 bg-transparent text-xs text-slate-600 dark:text-slate-300">
              <span>Qtd:</span>
              <span class="font-semibold">{{ itemsWithoutAgent.length }}</span>
              <span>| Valor:</span>
              <span class="font-semibold">{{ new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(totalWithoutAgent) }}</span>
            </div>
          </div>
        </div>
      </div>
      <!-- Fim do bloco Status e Cards sem agente -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-1 mb-4">
        <!-- Valor total por prioridade -->
        <div class="card-block card-header-valor-prioridade">
          <div class="card-block-header card-block-header-valor-prioridade">Valor por prioridade</div>
          <div class="flex gap-1 flex-wrap">
            <div v-for="(val, prio) in valueByPriority" :key="prio"
              :class="'flex items-center gap-1 rounded-full px-2 py-1 text-xs font-semibold border ' +
                (prio === 'urgent' ? 'bg-red-100 border-red-300 text-red-700 dark:bg-red-900/40 dark:border-red-700 dark:text-red-300' :
                 prio === 'high' ? 'bg-purple-100 border-purple-300 text-purple-700 dark:bg-purple-900/40 dark:border-purple-700 dark:text-purple-300' :
                 prio === 'medium' ? 'bg-yellow-100 border-yellow-300 text-yellow-700 dark:bg-yellow-900/40 dark:border-yellow-700 dark:text-yellow-300' :
                 prio === 'low' ? 'bg-green-100 border-green-300 text-green-700 dark:bg-green-900/40 dark:border-green-700 dark:text-green-300' :
                 'bg-slate-100 border-slate-300 text-slate-700 dark:bg-slate-800/40 dark:border-slate-700 dark:text-slate-300')">
              <span class="capitalize">{{ prio }}</span>
              <span class="font-semibold">{{ new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(val) }}</span>
              <span class="opacity-60">({{ percentByPriority[prio] }}%)</span>
            </div>
          </div>
        </div>
        <!-- Valor total por status -->
        <div class="card-block card-header-valor-status">
          <div class="card-block-header card-block-header-valor-status">Valor por status</div>
          <div class="flex gap-2 flex-wrap">
            <div v-for="(val, status) in valueByStatus" :key="status" :class="'flex items-center gap-1 rounded-full px-2 py-1 bg-transparent text-xs font-semibold ' + (status === 'open' ? 'border-slate-300 text-slate-700 bg-slate-100 dark:bg-slate-800/40 dark:text-slate-200' : status === 'won' ? 'border-green-300 text-green-700 bg-green-100 dark:bg-green-900/40 dark:text-green-300' : 'border-red-300 text-red-700 bg-red-100 dark:bg-red-900/40 dark:text-red-300') + ' border'">
              <span class="capitalize">{{ status }}</span>
              <span>{{ new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(val) }}</span>
              <span class="opacity-60">({{ percentByStatus[status] }}%)</span>
            </div>
          </div>
        </div>
        <!-- Valor médio por agente -->
        <div class="card-block card-header-valor-agente">
          <div class="card-block-header card-block-header-valor-agente">Valor médio por agente</div>
          <div class="flex gap-2 flex-wrap">
            <div v-for="agent in Object.values(avgByAgent)" :key="agent.id" class="flex items-center gap-1 border border-slate-200 dark:border-slate-700 rounded-full px-2 py-1 bg-transparent text-xs text-slate-600 dark:text-slate-300">
              <Avatar :name="agent.name" :src="agent.avatar_url" :size="18" />
              <span class="truncate max-w-[60px]">{{ agent.name }}</span>
              <span class="font-semibold">{{ new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(agent.avg) }}</span>
            </div>
          </div>
        </div>
        <!-- Card de maior e menor valor agrupados -->
        <div class="card-block card-header-maior-menor-valor">
          <div class="card-block-header card-block-header-maior-menor-valor">Card de maior e menor valor</div>
          <div class="flex flex-col md:flex-row gap-4">
            <div v-if="maxItem" class="flex-1 flex items-center gap-2 border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2 bg-transparent text-xs text-slate-700 dark:text-slate-200">
              <span class="font-semibold">Maior:</span>
              <span class="font-semibold">{{ maxItem.item_details?.title }}</span>
              <span>|</span>
              <span>{{ new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(parseFloat(maxItem.item_details?.value) || 0) }}</span>
              <span v-if="maxItem.agent">|</span>
              <span v-if="maxItem.agent">
                <Avatar :name="maxItem.agent.name" :src="maxItem.agent.avatar_url" :size="18" />
                {{ maxItem.agent.name }}
              </span>
            </div>
            <div v-if="minItem" class="flex-1 flex items-center gap-2 border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2 bg-transparent text-xs text-slate-700 dark:text-slate-200">
              <span class="font-semibold">Menor:</span>
              <span class="font-semibold">{{ minItem.item_details?.title }}</span>
              <span>|</span>
              <span>{{ new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(getMinItemValue) }}</span>
              <span v-if="minItem.agent">|</span>
              <span v-if="minItem.agent">
                <Avatar :name="minItem.agent.name" :src="minItem.agent.avatar_url" :size="18" />
                {{ minItem.agent.name }}
              </span>
            </div>
          </div>
        </div>
        <!-- Agendamentos -->
        <div class="card-block card-header-agendamentos col-span-1 md:col-span-2">
          <div class="card-block-header card-block-header-agendamentos flex items-center gap-2">
            <svg class="w-4 h-4 text-slate-500" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>
            Agendamentos
          </div>
          <div v-if="Object.keys(scheduleByDay).length" class="flex flex-col gap-2 mt-2">
            <div class="flex flex-wrap gap-3 items-center">
              <span class="flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400">
                Dia com mais agendamentos:
              </span>
              <span v-if="busiestDay" class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold bg-green-100 border border-green-300 text-green-700 dark:bg-green-900/40 dark:border-green-700 dark:text-green-300">
                {{ busiestDay }}
                <span class="ml-1">({{ scheduleByDay[busiestDay] }})</span>
                <span class="ml-2 text-slate-500 dark:text-slate-400 font-normal">{{ timeDiffLabel(busiestDay) }}</span>
              </span>
              <span class="flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400">
                Dia com menos agendamentos:
              </span>
              <span v-if="freestDay" class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold bg-blue-100 border border-blue-300 text-blue-700 dark:bg-blue-900/40 dark:border-blue-700 dark:text-blue-300">
                {{ freestDay }}
                <span class="ml-1">({{ scheduleByDay[freestDay] }})</span>
                <span class="ml-2 text-slate-500 dark:text-slate-400 font-normal">{{ timeDiffLabel(freestDay) }}</span>
              </span>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-2">
              <div>
                <div class="flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400 mb-1">
                  <!-- Ícone estrela para top dias mais cheios -->
                  <svg class="w-4 h-4 text-amber-500" fill="currentColor" viewBox="0 0 20 20"><path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.286 3.967a1 1 0 00.95.69h4.18c.969 0 1.371 1.24.588 1.81l-3.388 2.46a1 1 0 00-.364 1.118l1.287 3.966c.3.922-.755 1.688-1.54 1.118l-3.388-2.46a1 1 0 00-1.175 0l-3.388 2.46c-.784.57-1.838-.196-1.54-1.118l1.287-3.966a1 1 0 00-.364-1.118l-3.388-2.46c-.783-.57-.38-1.81.588-1.81h4.18a1 1 0 00.95-.69l1.286-3.967z"/></svg>
                  Top 3 dias mais cheios:
                </div>
                <div class="flex gap-1 flex-wrap">
                  <span v-for="d in top3Busiest" :key="d.day" class="badge-glass bg-green-50 border-green-200 text-green-700 dark:bg-green-900/40 dark:border-green-700 dark:text-green-300">
                    {{ d.day }} <span class="ml-1 font-semibold">({{ d.count }})</span>
                  </span>
                </div>
              </div>
              <div>
                <div class="flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400 mb-1">
                  <!-- Ícone círculo para top dias mais vazios -->
                  <svg class="w-4 h-4 text-orange-400" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6" /></svg>
                  Top 3 dias mais vazios:
                </div>
                <div class="flex gap-1 flex-wrap">
                  <span v-for="d in top3Freest" :key="d.day" class="badge-glass bg-orange-50 border-orange-200 text-orange-700 dark:bg-orange-900/40 dark:border-orange-700 dark:text-orange-300">
                    {{ d.day }} <span class="ml-1 font-semibold">({{ d.count }})</span>
                  </span>
                </div>
              </div>
            </div>
          </div>
          <div v-else class="text-xs text-slate-400 italic">Nenhum agendamento encontrado.</div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
const props = defineProps({
  title: String,
  color: String,
  items: Array,
  description: String,
  onClose: Function,
});

const values = computed(() => props.items.map(item => parseFloat(item.item_details?.value) || 0));

// Valores que realmente existem (não são null, undefined, string vazia ou 0 por falta de valor)
const valuesWithValue = computed(() => {
  return props.items
    .filter(item => item.item_details?.value !== null && 
                   item.item_details?.value !== undefined && 
                   item.item_details?.value !== '' &&
                   item.item_details?.value !== '0' &&
                   parseFloat(item.item_details?.value) !== 0)
    .map(item => parseFloat(item.item_details.value));
});

// Items que têm valor zero ou sem valor
const itemsWithoutValue = computed(() => {
  return props.items.filter(item => 
    !item.item_details?.value || 
    item.item_details?.value === '' ||
    item.item_details?.value === '0' ||
    parseFloat(item.item_details?.value) === 0
  );
});

const formattedTotal = computed(() => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(values.value.reduce((a, b) => a + b, 0)));
const formattedAvg = computed(() => values.value.length ? new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(values.value.reduce((a, b) => a + b, 0) / values.value.length) : '—');
const formattedMax = computed(() => values.value.length ? new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(Math.max(...values.value)) : '—');

const formattedMin = computed(() => {
  if (values.value.length === 0) return '—';
  
  // Se não há nenhum item com valor, retornar —
  if (valuesWithValue.value.length === 0) return '—';
  
  // Sempre calcular o menor valor apenas entre os itens que têm valor
  const minValueFromItemsWithValue = Math.min(...valuesWithValue.value);
  
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(minValueFromItemsWithValue);
});

// Card de maior valor e menor valor
const maxItem = computed(() => props.items.reduce((max, item) => (parseFloat(item.item_details?.value) > parseFloat(max?.item_details?.value || 0) ? item : max), null));

const minItem = computed(() => {
  // Sempre encontrar o item com menor valor entre os que têm valor, ignorando os sem valor
  if (valuesWithValue.value.length > 0) {
    return props.items.reduce((min, item) => {
      const currentValue = parseFloat(item.item_details?.value);
      const minValue = parseFloat(min?.item_details?.value || Infinity);
      
      // Só considerar itens que realmente têm valor
      if (item.item_details?.value && 
          item.item_details?.value !== '' &&
          item.item_details?.value !== '0' &&
          currentValue !== 0 &&
          currentValue < minValue) {
        return item;
      }
      return min;
    }, null);
  }
  
  return null;
});

// Valor do item de menor valor para exibição
const getMinItemValue = computed(() => {
  if (!minItem.value) return 0;
  
  // Sempre retornar o valor real do item (pois agora minItem sempre é um item com valor)
  return parseFloat(minItem.value.item_details?.value) || 0;
});

// Datas
const sortedByDate = computed(() => [...props.items].sort((a, b) => new Date(a.created_at) - new Date(b.created_at)));
const oldestDate = computed(() => sortedByDate.value[0]?.created_at ? new Date(sortedByDate.value[0].created_at) : null);
const newestDate = computed(() => sortedByDate.value[sortedByDate.value.length - 1]?.created_at ? new Date(sortedByDate.value[sortedByDate.value.length - 1].created_at) : null);

// Cards sem agente
const itemsWithoutAgent = computed(() => props.items.filter(item => !item.agent));
const totalWithoutAgent = computed(() => itemsWithoutAgent.value.reduce((sum, item) => sum + (parseFloat(item.item_details?.value) || 0), 0));

// Valor total por prioridade
const valueByPriority = computed(() => {
  const map = {};
  props.items.forEach(item => {
    const prio = item.item_details?.priority || 'none';
    map[prio] = (map[prio] || 0) + (parseFloat(item.item_details?.value) || 0);
  });
  return map;
});
// Valor total por status
const valueByStatus = computed(() => {
  const map = {};
  props.items.forEach(item => {
    const status = item.item_details?.status || 'open';
    map[status] = (map[status] || 0) + (parseFloat(item.item_details?.value) || 0);
  });
  return map;
});
// Valor médio por agente
const avgByAgent = computed(() => {
  const map = {};
  props.items.forEach(item => {
    const agent = item.item_details?.agent;
    if (agent && agent.id) {
      if (!map[agent.id]) map[agent.id] = { ...agent, total: 0, count: 0 };
      map[agent.id].total += parseFloat(item.item_details?.value) || 0;
      map[agent.id].count++;
    }
  });
  Object.values(map).forEach(a => { a.avg = a.count ? a.total / a.count : 0; });
  return map;
});
// Percentual por prioridade
const percentByPriority = computed(() => {
  const total = props.items.length;
  const map = {};
  props.items.forEach(item => {
    const prio = item.item_details?.priority || 'none';
    map[prio] = (map[prio] || 0) + 1;
  });
  Object.keys(map).forEach(k => { map[k] = ((map[k] / total) * 100).toFixed(1); });
  return map;
});
// Percentual por status
const percentByStatus = computed(() => {
  const total = props.items.length;
  const map = {};
  props.items.forEach(item => {
    const status = item.item_details?.status || 'open';
    map[status] = (map[status] || 0) + 1;
  });
  Object.keys(map).forEach(k => { map[k] = ((map[k] / total) * 100).toFixed(1); });
  return map;
});

const agentMap = computed(() => {
  const map = new Map();
  props.items.forEach(item => {
    const agent = item.item_details?.agent;
    if (agent && agent.id) {
      if (!map.has(agent.id)) {
        map.set(agent.id, { ...agent, count: 1 });
      } else {
        map.get(agent.id).count++;
      }
    }
  });
  return map;
});
const topAgents = computed(() => Array.from(agentMap.value.values()).sort((a, b) => b.count - a.count).slice(0, 5));
const extraAgents = computed(() => Math.max(0, agentMap.value.size - 5));

const priorities = computed(() => {
  const prioList = [
    { key: 'urgent', label: 'Urgente', class: 'bg-red-600', count: 0 },
    { key: 'high', label: 'Alta', class: 'bg-ruby-500', count: 0 },
    { key: 'medium', label: 'Média', class: 'bg-yellow-500', count: 0 },
    { key: 'low', label: 'Baixa', class: 'bg-green-500', count: 0 },
    { key: 'none', label: 'Nenhuma', class: 'bg-slate-300', count: 0 },
  ];
  props.items.forEach(item => {
    const prio = item.item_details?.priority || 'none';
    const found = prioList.find(p => p.key === prio);
    if (found) found.count++;
  });
  return prioList;
});

const statusList = computed(() => {
  const statusArr = [
    { key: 'open', label: 'Aberto', class: 'bg-slate-400', count: 0 },
    { key: 'won', label: 'Ganho', class: 'bg-green-600', count: 0 },
    { key: 'lost', label: 'Perdido', class: 'bg-red-600', count: 0 },
  ];
  props.items.forEach(item => {
    const status = item.item_details?.status || 'open';
    const found = statusArr.find(s => s.key === status);
    if (found) found.count++;
  });
  return statusArr;
});

// Agendamento por dia
const scheduleByDay = computed(() => {
  const map = {};
  props.items.forEach(item => {
    const d = item.item_details?.deadline_at;
    if (d) {
      const day = new Date(d).toLocaleDateString('pt-BR');
      map[day] = (map[day] || 0) + 1;
    }
  });
  return map;
});
const sortedDays = computed(() => {
  return Object.entries(scheduleByDay.value)
    .map(([day, count]) => ({ day, count }))
    .sort((a, b) => b.count - a.count);
});
const busiestDay = computed(() => sortedDays.value.length ? sortedDays.value[0].day : null);
const freestDay = computed(() => {
  // menor > 0
  const filtered = sortedDays.value.filter(d => d.count > 0);
  return filtered.length ? filtered[filtered.length - 1].day : null;
});
const top3Busiest = computed(() => sortedDays.value.slice(0, 3));
const top3Freest = computed(() => {
  const filtered = sortedDays.value.filter(d => d.count > 0);
  return filtered.slice(-3);
});

// Função utilitária para estimar o tempo até a data (em relação a hoje)
function timeDiffLabel(dateStr) {
  if (!dateStr) return '';
  const [day, month, year] = dateStr.split('/').map(Number);
  const date = new Date(year, month - 1, day);
  const today = new Date();
  today.setHours(0,0,0,0);
  const diffMs = date - today;
  const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24));
  if (diffDays === 0) return 'hoje';
  if (diffDays === 1) return 'amanhã';
  if (diffDays === -1) return 'ontem';
  if (diffDays > 1) return `em ${diffDays} dias`;
  if (diffDays < -1) return `há ${Math.abs(diffDays)} dias`;
  return '';
}
</script>

<style scoped>
.metric-card-glass {
  @apply rounded-2xl p-6 flex flex-col items-center shadow-md border border-slate-100 dark:border-slate-800 bg-white/60 dark:bg-slate-800/60 backdrop-blur-[2px] transition-all duration-200 hover:shadow-lg;
  position: relative;
  overflow: hidden;
}
.metric-label-glass {
  @apply text-xs text-slate-500 dark:text-slate-400 mb-2 font-medium tracking-wide;
}
.metric-value-glass {
  @apply text-2xl font-extrabold text-slate-900 dark:text-slate-100;
  letter-spacing: -0.01em;
}
.metric-gradient-blue::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 0;
  background: linear-gradient(135deg, #60a5fa33 0%, transparent 100%);
}
.metric-gradient-green::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 0;
  background: linear-gradient(135deg, #34d39933 0%, transparent 100%);
}
.metric-gradient-orange::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 0;
  background: linear-gradient(135deg, #fbbf2433 0%, transparent 100%);
}
.metric-gradient-purple::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 0;
  background: linear-gradient(135deg, #a78bfa33 0%, transparent 100%);
}
.metric-gradient-pink::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 0;
  background: linear-gradient(135deg, #f472b633 0%, transparent 100%);
}
.metric-gradient-slate::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 0;
  background: linear-gradient(135deg, #cbd5e133 0%, transparent 100%);
}
.metric-gradient-success::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 0;
  background: linear-gradient(135deg, #bbf7d033 0%, transparent 100%);
}
.metric-gradient-danger::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 0;
  background: linear-gradient(135deg, #fecaca33 0%, transparent 100%);
}
.metric-card-glass > * {
  position: relative;
  z-index: 1;
}
.badge-glass {
  @apply inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium shadow-sm backdrop-blur-[2px] transition-all duration-200;
}
.text-slate-700 span, .text-slate-700 {
  letter-spacing: -0.01em;
}
@media (max-width: 640px) {
  .mb-6.flex {
    gap: 0.25rem 0.75rem;
  }
}
.card-block {
  @apply border border-slate-200 dark:border-slate-700 rounded-2xl bg-white/80 dark:bg-slate-900/80 shadow-sm p-5 mb-4;
  position: relative;
  overflow: hidden;
}
.card-block-header {
  font-weight: 600;
  font-size: 0.85rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 0.5rem;
  padding: 0.5rem 0 0.5rem 0;
  border-radius: 0;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-left: 0;
  margin-right: 0;
  margin-top: -1.25rem;
  background: none;
  border-bottom: 1px solid #e5e7eb;
}
.card-block-header > span, .card-block-header > div, .card-block-header > h3, .card-block-header > h4, .card-block-header > h5 {
  margin-left: 1rem !important;
  margin-right: 1rem !important;
}
.card-block-header-agentes {
  background: none !important;
  color: inherit !important;
}
.card-block-header-prioridades {
  background: none !important;
  color: inherit !important;
}
.card-block-header-status {
  background: none !important;
  color: inherit !important;
}
.card-block-header-valor-prioridade {
  background: none !important;
  color: inherit !important;
}
.card-block-header-valor-status {
  background: none !important;
  color: inherit !important;
}
.card-block-header-valor-agente {
  background: none !important;
  color: inherit !important;
}
.card-block-header-sem-agente {
  background: none !important;
  color: inherit !important;
}
.card-block-header-maior-menor-valor {
  background: none !important;
  color: inherit !important;
}
.card-block-header-datas {
  background: none !important;
  color: inherit !important;
}
.card-block-header-agendamentos {
  background: none !important;
  color: inherit !important;
}

/* Ocultar scrollbar */
.scrollbar-hidden {
  scrollbar-width: none; /* Firefox */
  -ms-overflow-style: none; /* Internet Explorer 10+ */
}

.scrollbar-hidden::-webkit-scrollbar {
  display: none; /* Chrome, Safari e Opera */
}
</style> 