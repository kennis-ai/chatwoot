<script setup>
import { computed } from 'vue';
import ReportMetricCard from './ReportMetricCard.vue';

const props = defineProps({
  metrics: {
    type: Object,
    required: true,
  },
  formatCurrency: {
    type: Function,
    required: true,
  },
});

const totalItems = computed(() =>
  (props.metrics.totalItems || 0).toLocaleString()
);
const totalValue = computed(() =>
  props.formatCurrency(props.metrics.totalValue || 0)
);
const totalContacts = computed(() =>
  (props.metrics.contactMetrics?.totalContacts || 0).toLocaleString()
);
const totalConversations = computed(() =>
  (props.metrics.activityMetrics?.itemsWithConversations || 0).toLocaleString()
);
const avgValue = computed(() =>
  props.formatCurrency(props.metrics.averageValue || 0)
);
const itemsCreatedToday = computed(() =>
  (props.metrics.stageMetrics?.itemsCreatedToday || 0).toLocaleString()
);
const itemsCreatedThisWeek = computed(() =>
  (props.metrics.stageMetrics?.itemsCreatedThisWeek || 0).toLocaleString()
);
const itemsCreatedThisMonth = computed(() =>
  (props.metrics.stageMetrics?.itemsCreatedThisMonth || 0).toLocaleString()
);
const totalOffers = computed(() =>
  (props.metrics.stageMetrics?.totalOffers || 0).toLocaleString()
);
const avgOffersValue = computed(() =>
  props.formatCurrency(props.metrics.stageMetrics?.avgOffersValue || 0)
);
const itemsWithChecklists = computed(() =>
  (props.metrics.checklistMetrics?.itemsWithChecklists || 0).toLocaleString()
);
const checklistCompletionRate = computed(
  () =>
    `${((props.metrics.checklistMetrics?.completionRate || 0) * 100).toFixed(1)}%`
);
const itemsWithDeadline = computed(() =>
  (props.metrics.stageMetrics?.itemsWithDeadline || 0).toLocaleString()
);
const itemsWithAttachments = computed(() =>
  (props.metrics.activityMetrics?.itemsWithAttachments || 0).toLocaleString()
);
const itemsWithNotes = computed(() =>
  (props.metrics.activityMetrics?.itemsWithNotes || 0).toLocaleString()
);
const itemsWithRescheduling = computed(() =>
  (props.metrics.stageMetrics?.itemsWithRescheduling || 0).toLocaleString()
);
const itemsWithOffers = computed(() =>
  (props.metrics.stageMetrics?.itemsWithOffers || 0).toLocaleString()
);
const avgActivitiesPerItem = computed(() =>
  (
    props.metrics.activityMetrics?.averageActivitiesPerItem || 0
  ).toLocaleString()
);
</script>

<template>
  <div
    class="flex flex-wrap mx-0 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5 gap-4"
  >
    <ReportMetricCard
      label="Itens Totais"
      :value="totalItems"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Valor Total"
      :value="totalValue"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Valor Médio"
      :value="avgValue"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Itens Criados Hoje"
      :value="itemsCreatedToday"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Itens Criados na Semana"
      :value="itemsCreatedThisWeek"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Itens Criados no Mês"
      :value="itemsCreatedThisMonth"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Total de Ofertas"
      :value="totalOffers"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Valor Médio das Ofertas"
      :value="avgOffersValue"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Cards com Checklist"
      :value="itemsWithChecklists"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Taxa de Conclusão de Checklist"
      :value="checklistCompletionRate"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Cards com Deadline"
      :value="itemsWithDeadline"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Cards com Anexos"
      :value="itemsWithAttachments"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Cards com Notas"
      :value="itemsWithNotes"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Cards com Conversa"
      :value="itemsWithConversations"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Cards com Reagendamento"
      :value="itemsWithRescheduling"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Cards com Ofertas"
      :value="itemsWithOffers"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Média de Atividades por Item"
      :value="avgActivitiesPerItem"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Total de Contatos"
      :value="totalContacts"
      info-text=""
      class="flex-1"
    />
    <ReportMetricCard
      label="Conversas"
      :value="totalConversations"
      info-text=""
      class="flex-1"
    />
  </div>
</template>
