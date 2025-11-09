<script>
import { useAlert, useTrack } from 'dashboard/composables';
import { mapGetters, mapActions } from 'vuex';
import ReportFilterSelector from './components/FilterSelector.vue';
import V4Button from 'dashboard/components-next/button/Button.vue';
import ReportHeader from './components/ReportHeader.vue';
import kanbanAPI from '../../../../api/kanban';
import funnelAPI from '../../../../api/funnel';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import { generateFileName } from '../../../../helper/downloadHelper';
import KanbanMetrics from './components/KanbanMetrics.vue';
import StatusDistributionChart from './components/StatusDistributionChart.vue';
import ValueByPriorityChart from './components/ValueByPriorityChart.vue';
import ValueByStatusChart from './components/ValueByStatusChart.vue';

export default {
  name: 'KanbanReports',
  components: {
    ReportFilterSelector,
    V4Button,
    ReportHeader,
    KanbanMetrics,
    StatusDistributionChart,
    ValueByPriorityChart,
    ValueByStatusChart,
  },
  data() {
    const today = new Date();
    const thirtyDaysAgo = new Date(today);
    thirtyDaysAgo.setDate(today.getDate() - 30);

    return {
      activeTab: 'overview', // Aba ativa (overview ou productivity)
      from: thirtyDaysAgo.getTime(),
      to: today.getTime(),
      userIds: [],
      inbox: null,
      metrics: {
        totalItems: 0,
        itemsByStage: {},
        averageValue: 0,
        totalValue: 0,
        avgTimeInStage: {},
        conversionRates: {},
        stageMetrics: {
          valueByStage: {},
          itemsCreatedToday: 0,
          itemsCreatedThisWeek: 0,
          itemsCreatedThisMonth: 0,
          stageVelocity: {},
          avgTimeToConversion: {},
          stageEfficiency: {},
          itemsWithDeadline: 0,
          itemsWithRescheduling: 0,
          itemsWithOffers: 0,
          avgOffersValue: 0,
          totalOffers: 0,
          offerRanges: {
            low: 0, // Até R$ 1.000
            medium: 0, // R$ 1.001 a R$ 5.000
            high: 0, // Acima de R$ 5.000
          },
          priorityDistribution: {
            low: 0,
            medium: 0,
            high: 0,
          },
          channelDistribution: {},
        },
        funnelMetrics: {
          totalFunnels: 0,
          activeStages: 0,
          stageDistribution: {},
          averageStagesPerFunnel: 0,
          conversionByStage: {},
          timeInStageByFunnel: {},
          valueByStage: {},
          stageColors: {},
          messageTemplates: {},
          stagePositions: {},
        },
        checklistMetrics: {
          totalTasks: 0,
          completedTasks: 0,
          completionRate: 0,
          itemsWithChecklists: 0,
          averageTasksPerItem: 0,
        },
        activityMetrics: {
          totalActivities: 0,
          activitiesByType: {},
          averageActivitiesPerItem: 0,
          itemsWithNotes: 0,
          itemsWithAttachments: 0,
          stageChanges: 0,
          valueChanges: 0,
          agentChanges: 0,
          itemsWithConversations: 0,
        },
        contactMetrics: {
          totalContacts: new Set(),
          contactsWithEmail: 0,
          contactsWithPhone: 0,
          contactsWithBoth: 0,
        },
      },
      isLoading: false,
      funnels: [],
      maxHourlyChanges: 0,
      items: [],
    };
  },
  computed: {
    ...mapGetters('funnel', ['getFunnels', 'getSelectedFunnel', 'getUIFlags']),
    selectedFunnel() {
      return this.getSelectedFunnel;
    },
    funnelsFromStore() {
      return this.getFunnels;
    },
    defaultCurrency() {
      const i18nLocale = this.$i18n.locale || 'pt-BR';
      const currencyMap = {
        'pt-BR': { code: 'BRL', locale: 'pt-BR', symbol: 'R$' },
        pt_BR: { code: 'BRL', locale: 'pt-BR', symbol: 'R$' },
        'en-US': { code: 'USD', locale: 'en-US', symbol: '$' },
        en_US: { code: 'USD', locale: 'en-US', symbol: '$' },
        en: { code: 'USD', locale: 'en-US', symbol: '$' },
        'de-DE': { code: 'EUR', locale: 'de-DE', symbol: '€' },
        de_DE: { code: 'EUR', locale: 'de-DE', symbol: '€' },
        de: { code: 'EUR', locale: 'de-DE', symbol: '€' },
        'es-ES': { code: 'EUR', locale: 'es-ES', symbol: '€' },
        es_ES: { code: 'EUR', locale: 'es-ES', symbol: '€' },
        es: { code: 'EUR', locale: 'es-ES', symbol: '€' },
        'fr-FR': { code: 'EUR', locale: 'fr-FR', symbol: '€' },
        fr_FR: { code: 'EUR', locale: 'fr-FR', symbol: '€' },
        fr: { code: 'EUR', locale: 'fr-FR', symbol: '€' },
        'pt-PT': { code: 'EUR', locale: 'pt-PT', symbol: '€' },
        pt_PT: { code: 'EUR', locale: 'pt-PT', symbol: '€' },
      };

      return currencyMap[i18nLocale] || currencyMap['pt-BR'];
    },
    requestPayload() {
      const payload = {};
      if (this.from) payload.from = this.from;
      if (this.to) payload.to = this.to;
      if (this.userIds && this.userIds.length > 0) {
        // Extrair apenas os IDs dos agentes, não os objetos completos
        payload.user_ids = this.userIds.map(agent =>
          typeof agent === 'object' ? agent.id : agent
        );
      }
      if (this.inbox) payload.inbox_id = this.inbox;
      // Só incluir funnel_id se não for "all" (todos os funis)
      if (this.selectedFunnel?.id && this.selectedFunnel.id !== 'all') {
        payload.funnel_id = this.selectedFunnel.id;
      }
      return payload;
    },
    // Helper para garantir que items seja sempre um array
    safeItems() {
      return Array.isArray(this.items) ? this.items : [];
    },
    defaultChartOptions() {
      return {
        responsive: true,
        maintainAspectRatio: false,
        interaction: {
          mode: 'index',
          intersect: false,
        },
        animation: {
          duration: 750,
          easing: 'easeInOutQuart',
        },
        plugins: {
          legend: {
            position: 'bottom',
            labels: {
              usePointStyle: true,
              padding: 20,
              font: {
                family: "'Inter', sans-serif",
                size: 12,
              },
              color: '#94a3b8',
            },
          },
          tooltip: {
            backgroundColor: 'rgba(30, 41, 59, 0.95)',
            titleColor: '#e2e8f0',
            bodyColor: '#e2e8f0',
            borderColor: '#334155',
            borderWidth: 1,
            padding: 12,
            cornerRadius: 8,
            displayColors: true,
            usePointStyle: true,
            callbacks: {
              label: function (context) {
                let label = context.dataset.label || '';
                if (label) {
                  label += ': ';
                }
                if (context.parsed.y !== null) {
                  label += context.parsed.y.toLocaleString();
                }
                return label;
              },
            },
          },
        },
        scales: {
          y: {
            beginAtZero: true,
            grid: {
              color: 'rgba(51, 65, 85, 0.1)',
              drawBorder: false,
            },
            ticks: {
              color: '#94a3b8',
              padding: 10,
              font: {
                family: "'Inter', sans-serif",
                size: 11,
              },
            },
          },
          x: {
            grid: {
              display: false,
            },
            ticks: {
              color: '#94a3b8',
              padding: 10,
              font: {
                family: "'Inter', sans-serif",
                size: 11,
              },
            },
          },
        },
      };
    },
    isAllFunnelsFilter() {
      return this.selectedFunnel?.id === 'all' || !this.selectedFunnel?.id;
    },
    lineChartOptions() {
      return {
        ...this.defaultChartOptions,
        plugins: {
          ...this.defaultChartOptions.plugins,
          tooltip: {
            ...this.defaultChartOptions.plugins.tooltip,
            intersect: false,
            mode: 'nearest',
          },
        },
        elements: {
          line: {
            tension: 0.4,
          },
          point: {
            radius: 4,
            hoverRadius: 6,
            backgroundColor: '#fff',
            borderWidth: 3,
          },
        },
      };
    },
    pieChartOptions() {
      return {
        ...this.defaultChartOptions,
        cutout: '60%',
        plugins: {
          ...this.defaultChartOptions.plugins,
          tooltip: {
            ...this.defaultChartOptions.plugins.tooltip,
            callbacks: {
              label: context => {
                const value = context.parsed;
                const total = context.dataset.data.reduce((a, b) => a + b, 0);
                const percentage = ((value * 100) / total).toFixed(1);
                return `${
                  context.label
                }: ${value.toLocaleString()} (${percentage}%)`;
              },
            },
          },
        },
      };
    },
    barChartOptions() {
      return {
        ...this.defaultChartOptions,
        plugins: {
          ...this.defaultChartOptions.plugins,
          tooltip: {
            ...this.defaultChartOptions.plugins.tooltip,
            callbacks: {
              label: context => {
                return `${context.dataset.label}: ${this.formatCurrency(
                  context.parsed.y
                )}`;
              },
            },
          },
        },
        scales: {
          ...this.defaultChartOptions.scales,
          y: {
            ...this.defaultChartOptions.scales.y,
            ticks: {
              ...this.defaultChartOptions.scales.y.ticks,
              callback: value => this.formatCurrency(value),
            },
          },
        },
      };
    },
    radarChartOptions() {
      return {
        ...this.defaultChartOptions,
        scales: {
          r: {
            beginAtZero: true,
            max: 100,
            ticks: {
              stepSize: 20,
              color: '#94a3b8',
              backdropColor: 'transparent',
            },
            grid: {
              color: 'rgba(51, 65, 85, 0.1)',
            },
            angleLines: {
              color: 'rgba(51, 65, 85, 0.1)',
            },
            pointLabels: {
              color: '#94a3b8',
              font: {
                family: "'Inter', sans-serif",
                size: 11,
              },
            },
          },
        },
        plugins: {
          ...this.defaultChartOptions.plugins,
          tooltip: {
            ...this.defaultChartOptions.plugins.tooltip,
            callbacks: {
              label: context => {
                return `${context.dataset.label}: ${context.parsed}%`;
              },
            },
          },
        },
      };
    },
    lineChartData() {
      const stages = Object.keys(this.metrics.itemsByStage);
      const sortedStages = stages.sort((a, b) => {
        return (
          (this.metrics.funnelMetrics.stagePositions[a] || 0) -
          (this.metrics.funnelMetrics.stagePositions[b] || 0)
        );
      });

      return {
        labels: sortedStages,
        datasets: [
          {
            label: 'Itens por Estágio',
            data: sortedStages.map(stage =>
              Number(this.metrics.itemsByStage[stage] || 0)
            ),
            fill: true,
            borderColor: '#3b82f6',
            backgroundColor: 'rgba(59, 130, 246, 0.1)',
            borderWidth: 2,
            pointBackgroundColor: '#fff',
            pointBorderColor: '#3b82f6',
            pointHoverBackgroundColor: '#3b82f6',
            pointHoverBorderColor: '#fff',
          },
        ],
      };
    },
    pieChartData() {
      const stages = Object.keys(this.metrics.itemsByStage);
      return {
        labels: stages,
        datasets: [
          {
            data: stages.map(stage =>
              Number(this.metrics.itemsByStage[stage] || 0)
            ),
            backgroundColor: stages.map(
              stage =>
                this.metrics.funnelMetrics.stageColors[stage] || '#94a3b8'
            ),
            borderWidth: 2,
            borderColor: '#1e293b',
            hoverOffset: 15,
          },
        ],
      };
    },
    barChartData() {
      const stages = Object.keys(this.metrics.stageMetrics.valueByStage);
      const sortedStages = stages.sort((a, b) => {
        return (
          (this.metrics.funnelMetrics.stagePositions[a] || 0) -
          (this.metrics.funnelMetrics.stagePositions[b] || 0)
        );
      });

      return {
        labels: sortedStages,
        datasets: [
          {
            label: 'Valor por Estágio',
            data: sortedStages.map(stage =>
              Number(this.metrics.stageMetrics.valueByStage[stage] || 0)
            ),
            backgroundColor: 'rgba(16, 185, 129, 0.2)',
            borderColor: '#10b981',
            borderWidth: 2,
            borderRadius: 6,
            hoverBackgroundColor: 'rgba(16, 185, 129, 0.4)',
          },
        ],
      };
    },
    radarChartData() {
      const stages = Object.keys(this.metrics.stageMetrics.stageEfficiency);
      return {
        labels: stages,
        datasets: [
          {
            label: 'Eficiência de Estágio',
            data: stages.map(stage =>
              Math.round(
                (this.metrics.stageMetrics.stageEfficiency[stage] || 0) * 100
              )
            ),
            backgroundColor: 'rgba(139, 92, 246, 0.2)',
            borderColor: '#8b5cf6',
            borderWidth: 2,
            pointBackgroundColor: '#fff',
            pointBorderColor: '#8b5cf6',
            pointHoverBackgroundColor: '#8b5cf6',
            pointHoverBorderColor: '#fff',
            pointRadius: 4,
            pointHoverRadius: 6,
          },
        ],
      };
    },
    calendarData() {
      const today = new Date();
      const data = [];
      let maxValue = 0;

      // Gerar dados dos últimos 365 dias
      for (let i = 0; i < 365; i += 1) {
        const date = new Date(today);
        date.setDate(date.getDate() - i);
        const value = Math.floor(Math.random() * 5); // Valor entre 0 e 5 para simular atividades
        maxValue = Math.max(maxValue, value);
        data.push({
          day: date.toISOString().split('T')[0],
          value: Number(value),
        });
      }

      return data;
    },
    statusChartData() {
      // Status: Aberto, Ganho, Perdido
      const statusMap = { open: 0, won: 0, lost: 0 };
      this.safeItems.forEach(item => {
        const status = item.item_details?.status || 'open';
        if (statusMap[status] !== undefined) statusMap[status]++;
      });
      return {
        labels: ['Aberto', 'Ganho', 'Perdido'],
        values: [statusMap.open, statusMap.won, statusMap.lost],
        colors: ['#94a3b8', '#22c55e', '#ef4444'],
      };
    },
    valueByPriorityChartData() {
      // Prioridades: urgent, high, medium, low, none
      const prioList = [
        { key: 'urgent', label: 'Urgente', color: '#ef4444' },
        { key: 'high', label: 'Alta', color: '#a21caf' },
        { key: 'medium', label: 'Média', color: '#f59e0b' },
        { key: 'low', label: 'Baixa', color: '#22c55e' },
        { key: 'none', label: 'Nenhuma', color: '#94a3b8' },
      ];
      const valueMap = {};
      const countMap = {};
      this.safeItems.forEach(item => {
        const prio = item.item_details?.priority || 'none';
        valueMap[prio] =
          (valueMap[prio] || 0) + (parseFloat(item.item_details?.value) || 0);
        countMap[prio] = (countMap[prio] || 0) + 1;
      });
      const total = Object.values(countMap).reduce((a, b) => a + b, 0) || 1;
      return {
        labels: prioList.map(p => p.label),
        values: prioList.map(p => valueMap[p.key] || 0),
        colors: prioList.map(p => p.color),
        percents: prioList.map(p =>
          (((countMap[p.key] || 0) / total) * 100).toFixed(1)
        ),
      };
    },
    valueByStatusChartData() {
      // Status: open, won, lost
      const statusList = [
        { key: 'open', label: 'Aberto', color: '#94a3b8' },
        { key: 'won', label: 'Ganho', color: '#22c55e' },
        { key: 'lost', label: 'Perdido', color: '#ef4444' },
      ];
      const valueMap = {};
      const countMap = {};
      this.safeItems.forEach(item => {
        const status = item.item_details?.status || 'open';
        valueMap[status] =
          (valueMap[status] || 0) + (parseFloat(item.item_details?.value) || 0);
        countMap[status] = (countMap[status] || 0) + 1;
      });
      const total = Object.values(countMap).reduce((a, b) => a + b, 0) || 1;
      return {
        labels: statusList.map(s => s.label),
        values: statusList.map(s => valueMap[s.key] || 0),
        colors: statusList.map(s => s.color),
        percents: statusList.map(s =>
          (((countMap[s.key] || 0) / total) * 100).toFixed(1)
        ),
      };
    },
    stageDistributionPieData() {
      const stages = Object.keys(this.metrics.itemsByStage || {});
      const stageColors = this.metrics.funnelMetrics?.stageColors || {};

      const data = stages
        .map(stage => {
          const normalizedStage = stage.toLowerCase();
          const color = stageColors[normalizedStage] || '#94a3b8';

          // Buscar o nome da etapa nos dados dos funis
          let stageName = stage;
          if (this.funnels && this.funnels.length > 0) {
            for (const funnel of this.funnels) {
              if (
                funnel.stages &&
                funnel.stages[stage] &&
                funnel.stages[stage].name
              ) {
                stageName = funnel.stages[stage].name;
                break;
              }
            }
          }

          return {
            id: stage,
            label: stageName,
            value: Number(this.metrics.itemsByStage[stage] || 0),
            color: color,
          };
        })
        .filter(item => item.value > 0);

      return data;
    },
    topAgents() {
      // Top 5 agentes por quantidade de cards
      const map = new Map();
      this.safeItems.forEach(item => {
        const agent = item.item_details?.agent;
        if (agent && agent.id) {
          if (!map.has(agent.id)) {
            map.set(agent.id, { ...agent, count: 1 });
          } else {
            map.get(agent.id).count++;
          }
        }
      });
      return Array.from(map.values())
        .sort((a, b) => b.count - a.count)
        .slice(0, 5);
    },
    noAgentData() {
      // Cards sem agente
      const items = this.safeItems.filter(item => !item.item_details?.agent);
      const totalValue = items.reduce(
        (sum, item) => sum + (parseFloat(item.item_details?.value) || 0),
        0
      );
      return { count: items.length, totalValue };
    },
    maxMinValueData() {
      // Card de maior e menor valor
      const itemsWithValue = this.safeItems.filter(
        item => parseFloat(item.item_details?.value) > 0
      );
      if (!itemsWithValue.length) return { maxItem: null, minItem: null };
      const maxItem = itemsWithValue.reduce(
        (max, item) =>
          parseFloat(item.item_details?.value) >
          parseFloat(max?.item_details?.value || 0)
            ? item
            : max,
        null
      );
      const minItem = itemsWithValue.reduce(
        (min, item) =>
          parseFloat(item.item_details?.value) <
          parseFloat(min?.item_details?.value || Infinity)
            ? item
            : min,
        null
      );
      return { maxItem, minItem };
    },
    reportTabs() {
      return [
        { id: 'overview', label: 'Visão Geral' },
        { id: 'productivity', label: 'Produtividade' },
        { id: 'sales', label: 'Vendas' },
      ];
    },
    deadlineCardData() {
      const itemsWithDeadline = this.safeItems.filter(
        item => item.item_details?.deadline_at
      );
      const total = itemsWithDeadline.length;
      const totalValue = itemsWithDeadline.reduce(
        (sum, item) => sum + (parseFloat(item.item_details?.value) || 0),
        0
      );
      const avgValue = total ? totalValue / total : 0;
      const nextDeadline = itemsWithDeadline
        .map(item => new Date(item.item_details.deadline_at))
        .filter(date => !isNaN(date))
        .sort((a, b) => a - b)[0];
      const priorities = {};
      itemsWithDeadline.forEach(item => {
        const prio = item.item_details?.priority || 'none';
        priorities[prio] = (priorities[prio] || 0) + 1;
      });
      const mostCommonPriority =
        Object.entries(priorities).sort((a, b) => b[1] - a[1])[0]?.[0] || '-';
      return {
        total,
        totalValue,
        avgValue,
        nextDeadline: nextDeadline
          ? nextDeadline.toLocaleDateString('pt-BR')
          : '-',
        mostCommonPriority,
        percent: this.metrics.totalItems
          ? ((total / this.metrics.totalItems) * 100).toFixed(1)
          : '0',
      };
    },
    offersCardData() {
      const itemsWithOffers = this.safeItems.filter(
        item =>
          item.item_details?.offers &&
          Array.isArray(item.item_details.offers) &&
          item.item_details.offers.length > 0
      );
      const total = itemsWithOffers.length;
      let totalOffersValue = 0;
      let offerCount = 0;
      let maxOffer = null;
      let minOffer = null;
      let multiOfferCount = 0;
      const priorities = {};
      itemsWithOffers.forEach(item => {
        if (item.item_details.offers.length > 1) multiOfferCount++;
        const prio = item.item_details?.priority || 'none';
        priorities[prio] = (priorities[prio] || 0) + 1;
        item.item_details.offers.forEach(offer => {
          if (offer.value !== undefined) {
            totalOffersValue += offer.value;
            offerCount++;
            if (maxOffer === null || offer.value > maxOffer)
              maxOffer = offer.value;
            if (minOffer === null || offer.value < minOffer)
              minOffer = offer.value;
          }
        });
      });
      const avgOfferValue = offerCount ? totalOffersValue / offerCount : 0;
      const mostCommonPriority =
        Object.entries(priorities).sort((a, b) => b[1] - a[1])[0]?.[0] || '-';
      return {
        total,
        avgOfferValue,
        totalOffersValue,
        maxOffer,
        minOffer,
        multiOfferCount,
        mostCommonPriority,
        percent: this.metrics.totalItems
          ? ((total / this.metrics.totalItems) * 100).toFixed(1)
          : '0',
      };
    },
    productivityMetrics() {
      // Use real data from backend but override cycleAnalysis with local calculation
      const backendData = this.metrics.productivityMetrics || {};
      const cycleAnalysisResult = this.calculatedCycleAnalysis;

      return {
        conversionRate: backendData.conversionRate || 0,
        averageTicketWon: backendData.averageTicketWon || 0,
        totalValueLost: backendData.totalValueLost || 0,
        salesCycle: backendData.salesCycle || 0,
        checklistMetrics: backendData.checklistMetrics || {
          openItems: 0,
          wonItems: 0,
          lostItems: 0,
          totalItems: 0,
        },
        activityMetrics: backendData.activityMetrics || {
          byType: {
            stage_changed: 0,
            value_changed: 0,
            agent_changed: 0,
            note_added: 0,
            attachment_added: 0,
            checklist_item_added: 0,
            checklist_item_toggled: 0,
            conversation_linked: 0,
          },
          total: 0,
        },
        offersMetrics: backendData.offersMetrics || {
          itemsWithOffers: 0,
          averageOfferValue: 0,
          totalOffers: 0,
          percentageWithOffers: 0,
        },
        salesPerformance: backendData.salesPerformance || {
          won: 0,
          wonPercentage: 0,
          lost: 0,
          lostPercentage: 0,
          open: 0,
          openPercentage: 0,
        },
        // Always use locally calculated cycle analysis
        cycleAnalysis: cycleAnalysisResult,
      };
    },
    salesMetrics() {
      // Use real data from backend
      return (
        this.metrics.salesMetrics || {
          totalRevenue: 0,
          averageTicket: 0,
          closedDeals: 0,
          salesByChannel: {},
          funnelEfficiency: {},
          salesByCategory: {},
          salesByRegion: {},
          monthlyGoal: {
            target: 0,
            achieved: 0,
            percentage: 0,
          },
        }
      );
    },
    monthlyGoalFromFunnel() {
      // Calcular meta baseada nas configurações do funil selecionado
      const selectedFunnel = this.selectedFunnel;
      if (
        !selectedFunnel ||
        selectedFunnel.id === 'all' ||
        !this.funnels.length
      ) {
        return {
          target: 0,
          achieved: 0,
          percentage: 0,
          goalType: null,
          unit: null,
        };
      }

      // Encontrar o funil selecionado nos dados carregados
      const funnelData = this.funnels.find(
        f => String(f.id) === String(selectedFunnel.id)
      );
      if (
        !funnelData ||
        !funnelData.settings ||
        !funnelData.settings.goals ||
        funnelData.settings.goals.length === 0
      ) {
        return {
          target: 0,
          achieved: 0,
          percentage: 0,
          goalType: null,
          unit: null,
        };
      }

      // Pegar a primeira meta definida (pode haver múltiplas no futuro)
      const goal = funnelData.settings.goals[0];
      const goalType = goal.type;
      const goalValue = parseFloat(goal.value);
      const goalUnit = goal.unit;

      let achieved = 0;
      let target = goalValue;
      let percentage = 0;

      // Calcular o valor alcançado baseado no tipo da meta
      switch (goalType) {
        case 'conversion_rate':
          // Taxa de conversão baseada nos dados de produtividade
          achieved = this.productivityMetrics.conversionRate || 0;
          target = goalValue;
          percentage = target > 0 ? (achieved / target) * 100 : 0;
          break;

        case 'revenue':
          // Meta de receita
          achieved = this.salesMetrics.totalRevenue || 0;
          target = goalValue;
          percentage = target > 0 ? (achieved / target) * 100 : 0;
          break;

        case 'items_count':
          // Meta de quantidade de itens
          achieved = this.metrics.totalItems || 0;
          target = goalValue;
          percentage = target > 0 ? (achieved / target) * 100 : 0;
          break;

        default:
          // Tipo de meta não reconhecido
          achieved = 0;
          target = goalValue;
          percentage = 0;
      }

      return {
        target,
        achieved,
        percentage,
        goalType,
        unit: goalUnit,
      };
    },
    sortedTopCategories() {
      const categories = Object.entries(
        this.salesMetrics.salesByCategory || {}
      );
      return categories
        .sort(([, a], [, b]) => (b.value || 0) - (a.value || 0))
        .slice(0, 3);
    },
    remainingCategoriesValue() {
      const allCategories = Object.values(
        this.salesMetrics.salesByCategory || {}
      );
      const top3Value = this.sortedTopCategories.reduce(
        (sum, [, data]) => sum + (data.value || 0),
        0
      );
      const totalValue = allCategories.reduce(
        (sum, data) => sum + (data.value || 0),
        0
      );
      return Math.max(0, totalValue - top3Value);
    },
    sortedTopRegions() {
      const regions = Object.entries(this.salesMetrics.salesByRegion || {});
      return regions
        .sort(([, a], [, b]) => (b.value || 0) - (a.value || 0))
        .slice(0, 3);
    },
    remainingRegionsValue() {
      const allRegions = Object.values(this.salesMetrics.salesByRegion || {});
      const top3Value = this.sortedTopRegions.reduce(
        (sum, [, data]) => sum + (data.value || 0),
        0
      );
      const totalValue = allRegions.reduce(
        (sum, data) => sum + (data.value || 0),
        0
      );
      return Math.max(0, totalValue - top3Value);
    },
    calculatedCycleAnalysis() {
      // Calculate cycle analysis from items data
      const wonItems = this.safeItems.filter(
        item => item.item_details?.status === 'won'
      );

      if (wonItems.length === 0) {
        return {
          averageCycle: 0,
          bestCycle: 0,
          worstCycle: 0,
        };
      }

      const cycles = wonItems.map(item => {
        const createdAt = new Date(item.created_at);
        let endDate = new Date();

        // Try to find when the status was changed to 'won' in activities
        const wonActivity = item.activities?.find(
          activity =>
            activity.type === 'status_changed' &&
            activity.details?.new_status === 'won'
        );

        if (wonActivity) {
          endDate = new Date(wonActivity.created_at);
        } else {
          // If no specific activity, use the date of the last activity or updated_at as fallback
          const activities = item.activities || [];
          if (activities.length > 0) {
            // Use the date of the last activity
            const lastActivity = activities.sort(
              (a, b) => new Date(b.created_at) - new Date(a.created_at)
            )[0];
            endDate = new Date(lastActivity.created_at);
          } else {
            // Use updated_at as final fallback
            endDate = new Date(item.updated_at);
          }
        }

        const diffTime = Math.abs(endDate - createdAt);
        const diffDays = diffTime / (1000 * 60 * 60 * 24); // Keep as decimal

        return diffDays;
      });

      const averageCycle = cycles.reduce((a, b) => a + b, 0) / cycles.length;
      const bestCycle = Math.min(...cycles);
      const worstCycle = Math.max(...cycles);

      return {
        averageCycle: Number(averageCycle.toFixed(1)), // Round to 1 decimal
        bestCycle: Number(bestCycle.toFixed(1)),
        worstCycle: Number(worstCycle.toFixed(1)),
      };
    },
  },
  watch: {
    selectedFunnel: {
      handler(newFunnel, oldFunnel) {
        // Se o funil mudou (incluindo "all"), recarregar os dados
        // Mas não no primeiro carregamento (oldFunnel é undefined)
        if (oldFunnel !== undefined && newFunnel?.id !== oldFunnel?.id) {
          this.fetchAllData();
        }
      },
      immediate: false,
    },
  },
  async mounted() {
    console.log(
      '[KanbanReports] Componente montado, iniciando carregamento...'
    );

    // Carregar funis do store se necessário
    if (!this.funnelsFromStore || this.funnelsFromStore.length === 0) {
      await this.fetch();
    }

    // Forçar "Todos os Funis" como padrão inicial
    await this.setSelectedFunnel({
      id: 'all',
      name: 'Todos os Funis',
    });

    console.log('[KanbanReports] Funil inicial definido:', this.selectedFunnel);

    // Carregar os dados iniciais
    await this.fetchAllData();
  },
  methods: {
    ...mapActions('funnel', ['fetch', 'setSelectedFunnel']),
    async ensureFunnelSelected() {
      try {
        // Se não temos funis, buscar do store
        if (!this.funnelsFromStore || this.funnelsFromStore.length === 0) {
          await this.fetch();
        }

        // SEMPRE forçar "Todos os Funis" como padrão no reports
        // O fetch() pode ter setado um funil específico automaticamente
        if (!this.selectedFunnel || this.selectedFunnel.id !== 'all') {
          await this.setSelectedFunnel({
            id: 'all',
            name: 'Todos os Funis',
          });
          console.log('[KanbanReports] Funil inicial definido como "all"');
        }
      } catch (error) {
        console.error('Erro ao garantir funil selecionado:', error);
        try {
          const alert = useAlert();
          if (alert && alert.showAlert) {
            alert.showAlert(
              'Erro ao carregar funis. Verifique se existem funis configurados.'
            );
          }
        } catch (alertError) {
          console.error('Erro ao mostrar alerta:', alertError);
        }
      }
    },
    async fetchAllData() {
      try {
        this.isLoading = true;
        console.log(
          '[KanbanReports] fetchAllData iniciado com funil:',
          this.selectedFunnel?.id
        );
        // Primeiro carregar os funis para ter as cores das etapas
        await this.fetchFunnels();
        // Depois carregar as métricas
        await this.fetchMetrics();
      } catch (error) {
        console.error('Erro ao carregar métricas do Kanban:', error);
        // Usar try-catch para evitar erro de destructuring
        try {
          const alert = useAlert();
          if (alert && alert.showAlert) {
            alert.showAlert('Erro ao carregar métricas do Kanban');
          }
        } catch (alertError) {
          console.error('Erro ao mostrar alerta:', alertError);
        }
      } finally {
        this.isLoading = false;
      }
    },
    async fetchFunnels() {
      try {
        // Sempre fazer uma chamada direta ao funnelAPI para garantir dados frescos
        const response = await funnelAPI.getAll();

        // Tentar diferentes formatos de resposta
        if (response.data && Array.isArray(response.data)) {
          this.funnels = response.data;
        } else if (Array.isArray(response)) {
          this.funnels = response;
        } else {
          this.funnels = [];
        }

        this.calculateFunnelMetrics();
      } catch (error) {
        console.error('Erro ao carregar dados dos funis:', error);
        // Fallback para dados do store
        if (this.funnelsFromStore && this.funnelsFromStore.length > 0) {
          this.funnels = this.funnelsFromStore;
          this.calculateFunnelMetrics();
        } else {
          try {
            const alert = useAlert();
            if (alert && alert.showAlert) {
              alert.showAlert('Erro ao carregar dados dos funis');
            }
          } catch (alertError) {
            console.error('Erro ao mostrar alerta:', alertError);
          }
        }
      }
    },
    calculateFunnelMetrics() {
      const funnelMetrics = {
        totalFunnels: this.funnels.length,
        activeStages: 0,
        stageDistribution: {},
        averageStagesPerFunnel: 0,
        conversionByStage: {},
        timeInStageByFunnel: {},
        valueByStage: {},
        stageColors: {},
        messageTemplates: {},
        stagePositions: {},
      };

      // Primeiro, coletar todas as cores por nome de estágio (preserva a primeira cor encontrada)
      const stageColorsMap = {};

      this.funnels.forEach(funnel => {
        if (funnel.stages && typeof funnel.stages === 'object') {
          const stageKeys = Object.keys(funnel.stages);
          funnelMetrics.activeStages += stageKeys.length;

          // Distribuição de estágios e cores
          stageKeys.forEach(stageKey => {
            const stage = funnel.stages[stageKey];
            if (stage && stage.name) {
              // Usar a chave do stage (ex: "novo", "teste") como nome normalizado
              const normalizedName = stageKey.toLowerCase();

              funnelMetrics.stageDistribution[normalizedName] =
                (funnelMetrics.stageDistribution[normalizedName] || 0) + 1;

              // Só define a cor se ainda não foi definida para este nome de estágio
              if (!stageColorsMap[normalizedName]) {
                stageColorsMap[normalizedName] = stage.color || '#94a3b8';
              }

              funnelMetrics.stagePositions[normalizedName] =
                stage.position || 0;

              // Contagem de templates de mensagem por estágio
              if (
                stage.message_templates &&
                Array.isArray(stage.message_templates)
              ) {
                funnelMetrics.messageTemplates[normalizedName] =
                  (funnelMetrics.messageTemplates[normalizedName] || 0) +
                  stage.message_templates.length;
              }
            }
          });
        }
      });

      // Aplicar o mapeamento de cores consolidado
      funnelMetrics.stageColors = stageColorsMap;

      // Média de estágios por funil
      funnelMetrics.averageStagesPerFunnel =
        funnelMetrics.totalFunnels > 0
          ? funnelMetrics.activeStages / funnelMetrics.totalFunnels
          : 0;

      this.metrics.funnelMetrics = funnelMetrics;
    },
    async fetchMetrics() {
      try {
        // Usar o funil selecionado do store - enviar apenas parâmetros permitidos
        const params = {};
        // Só incluir funnel_id se não for "all" (todos os funis)
        if (this.selectedFunnel?.id && this.selectedFunnel.id !== 'all') {
          params.funnel_id = this.selectedFunnel.id;
          console.log(
            '[KanbanReports] Buscando dados do funil:',
            this.selectedFunnel.id
          );
        } else {
          console.log(
            '[KanbanReports] Buscando dados de TODOS OS FUNIS (sem funnel_id)'
          );
        }

        if (this.from) params.from = this.from;
        if (this.to) params.to = this.to;
        if (this.userIds && this.userIds.length > 0) {
          // Enviar array de IDs dos agentes
          params.user_ids = this.userIds.map(agent =>
            typeof agent === 'object' ? agent.id : agent
          );
        }
        if (this.inbox) params.inbox_id = this.inbox;

        console.log('[KanbanReports] Parâmetros para API:', params);
        console.log('[KanbanReports] selectedFunnel:', this.selectedFunnel);

        // Chamar o novo endpoint de reports
        const response = await kanbanAPI.getReports(params);

        // O backend agora retorna as métricas já calculadas
        this.metrics = {
          ...this.metrics,
          ...response.data,
        };

        // Buscar items apenas para os gráficos que precisam dos dados brutos
        const itemsResponse = await kanbanAPI.getItems(
          params.funnel_id,
          1,
          null,
          params.user_ids?.[0]
        );
        this.items = itemsResponse.data?.items || [];

        console.log(
          '[KanbanReports] Métricas carregadas. Total de items:',
          this.metrics.totalItems
        );
      } catch (error) {
        console.error('Erro ao carregar métricas do Kanban:', error);
        try {
          const alert = useAlert();
          if (alert && alert.showAlert) {
            alert.showAlert('Erro ao carregar métricas do Kanban');
          }
        } catch (alertError) {
          console.error('Erro ao mostrar alerta:', alertError);
        }
      }
    },
    calculateMetrics(items) {
      if (!Array.isArray(items)) {
        console.warn('calculateMetrics recebeu dados inválidos:', items);
        return this.metrics;
      }

      const metrics = {
        totalItems: items.length,
        itemsByStage: {},
        totalValue: 0,
        averageValue: 0,
        avgTimeInStage: {},
        conversionRates: {},
        stageMetrics: {
          valueByStage: {},
          itemsCreatedToday: 0,
          itemsCreatedThisWeek: 0,
          itemsCreatedThisMonth: 0,
          stageVelocity: {},
          avgTimeToConversion: {},
          stageEfficiency: {},
          itemsWithDeadline: 0,
          itemsWithRescheduling: 0,
          itemsWithOffers: 0,
          avgOffersValue: 0,
          totalOffers: 0,
          offerRanges: {
            low: 0, // Até R$ 1.000
            medium: 0, // R$ 1.001 a R$ 5.000
            high: 0, // Acima de R$ 5.000
          },
          priorityDistribution: {
            low: 0,
            medium: 0,
            high: 0,
          },
          channelDistribution: {},
        },
        checklistMetrics: {
          totalTasks: 0,
          completedTasks: 0,
          completionRate: 0,
          itemsWithChecklists: 0,
          averageTasksPerItem: 0,
        },
        activityMetrics: {
          totalActivities: 0,
          activitiesByType: {},
          averageActivitiesPerItem: 0,
          itemsWithNotes: 0,
          itemsWithAttachments: 0,
          stageChanges: 0,
          valueChanges: 0,
          agentChanges: 0,
          itemsWithConversations: 0,
        },
        contactMetrics: {
          totalContacts: new Set(),
          contactsWithEmail: 0,
          contactsWithPhone: 0,
          contactsWithBoth: 0,
        },
      };

      const today = new Date();
      const thisWeek = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000);
      const thisMonth = new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000);

      // Calcular métricas básicas e avançadas
      items.forEach(item => {
        if (!item) return; // Pular itens nulos/undefined

        const stage = item.funnel_stage || 'unknown';
        const details = item.item_details || {};
        const value = parseFloat(details?.value) || 0;
        const createdAt = new Date(item.created_at);
        const checklist = Array.isArray(details?.checklist)
          ? details.checklist
          : [];
        const activities = Array.isArray(details?.activities)
          ? details.activities
          : [];

        // Contagem por estágio
        metrics.itemsByStage[stage] = (metrics.itemsByStage[stage] || 0) + 1;

        // Valor total e por estágio
        metrics.totalValue += value;
        metrics.stageMetrics.valueByStage[stage] =
          (metrics.stageMetrics.valueByStage[stage] || 0) + value;

        // Contagem de itens recentes
        if (createdAt >= today.setHours(0, 0, 0, 0)) {
          metrics.stageMetrics.itemsCreatedToday += 1;
        }
        if (createdAt >= thisWeek) {
          metrics.stageMetrics.itemsCreatedThisWeek += 1;
        }
        if (createdAt >= thisMonth) {
          metrics.stageMetrics.itemsCreatedThisMonth += 1;
        }

        // Métricas de checklist
        if (checklist.length > 0) {
          metrics.checklistMetrics.itemsWithChecklists += 1;
          metrics.checklistMetrics.totalTasks += checklist.length;
          metrics.checklistMetrics.completedTasks += checklist.filter(
            task => task && task.completed
          ).length;
        }

        // Métricas de atividades
        if (activities.length > 0) {
          metrics.activityMetrics.totalActivities += activities.length;

          activities.forEach(activity => {
            if (activity && activity.type) {
              metrics.activityMetrics.activitiesByType[activity.type] =
                (metrics.activityMetrics.activitiesByType[activity.type] || 0) +
                1;

              if (activity.type === 'stage_changed') {
                metrics.activityMetrics.stageChanges += 1;
              } else if (activity.type === 'value_changed') {
                metrics.activityMetrics.valueChanges += 1;
              } else if (activity.type === 'note_added') {
                metrics.activityMetrics.itemsWithNotes += 1;
              } else if (activity.type === 'attachment_added') {
                metrics.activityMetrics.itemsWithAttachments += 1;
              } else if (activity.type === 'agent_changed') {
                metrics.activityMetrics.agentChanges += 1;
              }
            }
          });
        }

        // Métricas de prioridade
        if (details.priority) {
          const priority = details.priority;
          if (
            metrics.stageMetrics.priorityDistribution[priority] !== undefined
          ) {
            metrics.stageMetrics.priorityDistribution[priority] += 1;
          }
        }

        // Métricas de canal
        if (details.channel) {
          metrics.stageMetrics.channelDistribution[details.channel] =
            (metrics.stageMetrics.channelDistribution[details.channel] || 0) +
            1;
        }

        // Métricas de deadline e agendamento
        if (details.deadline_at) metrics.stageMetrics.itemsWithDeadline += 1;
        if (details.rescheduled)
          metrics.stageMetrics.itemsWithRescheduling += 1;

        // Métricas de ofertas
        if (
          details.offers &&
          Array.isArray(details.offers) &&
          details.offers.length > 0
        ) {
          metrics.stageMetrics.itemsWithOffers += 1;
          metrics.stageMetrics.totalOffers += details.offers.length;

          // Calcular valor total e médio das ofertas
          const offersTotal = details.offers.reduce(
            (sum, offer) => sum + (parseFloat(offer.value) || 0),
            0
          );
          metrics.stageMetrics.avgOffersValue =
            details.offers.length > 0 ? offersTotal / details.offers.length : 0;

          // Agrupar ofertas por faixa de valor
          details.offers.forEach(offer => {
            if (offer.value !== undefined) {
              const offerValue = parseFloat(offer.value);
              if (offerValue <= 1000) {
                metrics.stageMetrics.offerRanges.low += 1;
              } else if (offerValue <= 5000) {
                metrics.stageMetrics.offerRanges.medium += 1;
              } else {
                metrics.stageMetrics.offerRanges.high += 1;
              }
            }
          });
        }

        // Métricas de conversas
        if (item.conversation_display_id) {
          metrics.activityMetrics.itemsWithConversations += 1;
        }
      });

      // Calcular médias e taxas
      metrics.averageValue =
        items.length > 0 ? metrics.totalValue / items.length : 0;
      metrics.checklistMetrics.completionRate =
        metrics.checklistMetrics.totalTasks > 0
          ? metrics.checklistMetrics.completedTasks /
            metrics.checklistMetrics.totalTasks
          : 0;
      metrics.checklistMetrics.averageTasksPerItem =
        items.length > 0
          ? metrics.checklistMetrics.totalTasks / items.length
          : 0;
      metrics.activityMetrics.averageActivitiesPerItem =
        items.length > 0
          ? metrics.activityMetrics.totalActivities / items.length
          : 0;

      // Converter Set para número
      metrics.contactMetrics.totalContacts =
        metrics.contactMetrics.totalContacts.size;

      return metrics;
    },
    onFilterChange({
      from,
      to,
      groupBy,
      businessHours,
      selectedAgents,
      selectedLabel,
      selectedInbox,
      selectedTeam,
      selectedRating,
      selectedFunnel,
    } = {}) {
      const funnelChanged =
        selectedFunnel && selectedFunnel.id !== this.selectedFunnel?.id;

      if (from) this.from = from;
      if (to) this.to = to;
      if (selectedAgents) this.userIds = selectedAgents;
      if (selectedInbox) this.inbox = selectedInbox;

      // Atualizar o funil selecionado no store
      if (selectedFunnel) {
        if (selectedFunnel.id === 'all') {
          // Se "Todos os Funis" foi selecionado, definir selectedFunnel como objeto "all"
          this.setSelectedFunnel(selectedFunnel);
        } else if (this.funnelsFromStore) {
          // Se um funil específico foi selecionado, buscar do store
          const selectedFunnelFromStore = this.funnelsFromStore.find(
            f => String(f.id) === String(selectedFunnel.id)
          );
          if (selectedFunnelFromStore) {
            this.setSelectedFunnel(selectedFunnelFromStore);
          }
        }
      }

      try {
        const track = useTrack();
        if (track) {
          track(REPORTS_EVENTS.FILTER_REPORT, {
            filterType: 'kanban',
            filterValue: JSON.stringify(this.requestPayload),
          });
        }
      } catch (trackError) {
        console.error('Erro ao rastrear evento:', trackError);
      }

      // Se o funil mudou, o watcher vai chamar fetchAllData
      // Senão, chamar manualmente para outros filtros (data, agentes, etc)
      if (!funnelChanged) {
        this.fetchAllData();
      }
    },
    async downloadReports() {
      try {
        // Enviar apenas parâmetros permitidos
        const params = {};
        // Só incluir funnel_id se não for "all" (todos os funis)
        if (this.selectedFunnel?.id && this.selectedFunnel.id !== 'all') {
          params.funnel_id = String(this.selectedFunnel.id);
        }
        if (this.from) params.from = this.from;
        if (this.to) params.to = this.to;
        if (this.userIds && this.userIds.length > 0)
          params.user_ids = this.userIds;
        if (this.inbox) params.inbox_id = this.inbox;

        const response = await kanbanAPI.getItems(params);
        const items = response.data?.items || [];
        const csvContent = this.convertToCSV(items);
        const blob = new Blob([csvContent], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = generateFileName({ type: 'kanban_report', to: this.to });
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
      } catch (error) {
        console.error('Erro ao baixar relatório do Kanban:', error);
        try {
          const alert = useAlert();
          if (alert && alert.showAlert) {
            alert.showAlert('Erro ao baixar relatório do Kanban');
          }
        } catch (alertError) {
          console.error('Erro ao mostrar alerta:', alertError);
        }
      }
    },
    convertToCSV(items) {
      if (!Array.isArray(items)) {
        console.warn('convertToCSV recebeu dados inválidos:', items);
        return '';
      }

      const headers = [
        'ID',
        'Estágio',
        'Título',
        'Valor',
        'Data de Criação',
        'Data de Entrada no Estágio',
        'Descrição',
        'Prioridade',
        'Canal',
        'ID do Contato',
        'Email',
        'Telefone',
        'Data Limite',
        'Total de Atividades',
        'Total de Notas',
        'Total de Anexos',
      ].join(',');

      const rows = items
        .map(item => {
          if (!item) return '';

          const details = item.item_details || {};
          const activities = Array.isArray(details.activities)
            ? details.activities
            : [];
          const notes = activities.filter(
            a => a && a.type === 'note_added'
          ).length;
          const attachments = activities.filter(
            a => a && a.type === 'attachment_added'
          ).length;

          return [
            item.id || '',
            item.funnel_stage || '',
            (details.title || '').replace(/,/g, ';'),
            details.value || '',
            item.created_at || '',
            item.stage_entered_at || '',
            (details.description || '').replace(/,/g, ';'),
            details.priority || '',
            details.channel || '',
            details.contact_id || '',
            details.email || '',
            details.phone || '',
            details.deadline_at || '',
            activities.length,
            notes,
            attachments,
          ].join(',');
        })
        .filter(row => row !== ''); // Remover linhas vazias

      return [headers, ...rows].join('\n');
    },
    formatCurrency(value) {
      if (value === null || value === undefined || isNaN(value)) {
        const currency = this.defaultCurrency;
        return new Intl.NumberFormat(currency.locale, {
          style: 'currency',
          currency: currency.code,
        }).format(0);
      }

      const currency = this.defaultCurrency;

      // Formatação abreviada para valores grandes
      const absValue = Math.abs(value);
      if (absValue >= 1000000) {
        const millions = absValue / 1000000;
        const formatted =
          millions % 1 === 0 ? millions.toFixed(0) : millions.toFixed(1);
        return `${currency.symbol} ${formatted}M`;
      }

      try {
        return new Intl.NumberFormat(currency.locale, {
          style: 'currency',
          currency: currency.code,
        }).format(value);
      } catch (error) {
        console.error('[KanbanReports] formatCurrency error:', error);
        // Fallback se houver erro de formatação
        return `${currency.symbol} ${value.toFixed(2)}`;
      }
    },
    formatDuration(ms) {
      if (!ms || isNaN(ms)) return '0 dias';
      const days = Math.floor(ms / (1000 * 60 * 60 * 24));
      return `${days} ${days === 1 ? 'dia' : 'dias'}`;
    },
    formatPercentage(value) {
      if (value === null || value === undefined || isNaN(value)) {
        return '0%';
      }
      return `${(value * 100).toFixed(1)}%`;
    },
    getHourlyChanges() {
      const hourlyChanges = Array(24).fill(0);
      const activities = Object.values(
        this.metrics.activityMetrics.activitiesByType
      ).reduce((acc, val) => acc + (val || 0), 0);

      // Distribuir as atividades ao longo do dia com uma curva natural
      for (let i = 0; i < activities; i += 1) {
        // Simular uma distribuição mais realista com pico durante horário comercial
        const hour = Math.floor((Math.sin(Math.random() * Math.PI) + 1) * 12);
        hourlyChanges[hour] = (hourlyChanges[hour] || 0) + 1;
      }

      this.maxHourlyChanges = Math.max(...hourlyChanges);
      return hourlyChanges;
    },
    getCompletionTrendClass(type = 'text') {
      const progress = this.getCompletionProgress();
      const baseClass = type === 'bg' ? 'bg-' : 'text-';

      if (progress >= 80)
        return `${baseClass}emerald-500 dark:${baseClass}emerald-400`;
      if (progress >= 50)
        return `${baseClass}yellow-500 dark:${baseClass}yellow-400`;
      return `${baseClass}red-500 dark:${baseClass}red-400`;
    },
    getCompletionProgress() {
      const totalItems = this.metrics.totalItems;
      const completedItems = Object.values(this.metrics.itemsByStage).reduce(
        (acc, val) => acc + (val || 0),
        0
      );
      return totalItems > 0 ? (completedItems / totalItems) * 100 : 0;
    },
    getCompletionForecast() {
      const velocity = this.getWeeklyThroughput();
      const remainingItems =
        this.metrics.totalItems -
        Object.values(this.metrics.itemsByStage).reduce(
          (acc, val) => acc + (val || 0),
          0
        );
      const weeksToComplete = velocity > 0 ? remainingItems / velocity : 0;

      const date = new Date();
      date.setDate(date.getDate() + weeksToComplete * 7);

      return date.toLocaleDateString('pt-BR', {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
      });
    },
    identifyBottlenecks() {
      const bottlenecks = [];
      const stages = Object.keys(this.metrics.itemsByStage);

      stages.forEach(stage => {
        const itemCount = this.metrics.itemsByStage[stage];
        const avgTime = this.metrics.avgTimeInStage[stage];
        const efficiency = this.metrics.stageMetrics.stageEfficiency[stage];

        if (efficiency < 0.5 && itemCount > 0) {
          bottlenecks.push({
            stage,
            severity: 'high',
            reason: 'Baixa eficiência no processamento',
          });
        } else if (avgTime > 7 * 24 * 60 * 60 * 1000 && itemCount > 0) {
          bottlenecks.push({
            stage,
            severity: 'medium',
            reason: 'Tempo de permanência elevado',
          });
        }
      });

      return bottlenecks;
    },
    getBottleneckSeverityClass(severity) {
      const classes = {
        high: 'bg-red-500',
        medium: 'bg-yellow-500',
        low: 'bg-orange-500',
      };
      return classes[severity] || classes.medium;
    },
    getOptimizationSuggestions() {
      const suggestions = [];
      const stages = Object.keys(this.metrics.itemsByStage);

      // Análise de distribuição de trabalho
      const avgItemsPerStage =
        stages.length > 0 ? this.metrics.totalItems / stages.length : 0;
      stages.forEach(stage => {
        const items = this.metrics.itemsByStage[stage];
        if (items > avgItemsPerStage * 1.5) {
          suggestions.push({
            icon: 'i-ph-warning-circle',
            title: `Distribuição desbalanceada em ${stage}`,
            description:
              'Considere redistribuir o trabalho ou aumentar a capacidade neste estágio',
          });
        }
      });

      // Análise de eficiência
      const lowEfficiencyStages = stages.filter(
        stage => (this.metrics.stageMetrics.stageEfficiency[stage] || 0) < 0.6
      );
      if (lowEfficiencyStages.length > 0) {
        suggestions.push({
          icon: 'i-ph-trend-up',
          title: 'Oportunidade de melhoria na eficiência',
          description:
            'Alguns estágios apresentam baixa eficiência. Analise os processos e recursos',
        });
      }

      // Análise de valor
      const avgValue = this.metrics.averageValue;
      const lowValueStages = stages.filter(
        stage =>
          (this.metrics.stageMetrics.valueByStage[stage] || 0) < avgValue * 0.5
      );
      if (lowValueStages.length > 0) {
        suggestions.push({
          icon: 'i-ph-currency-circle-dollar',
          title: 'Otimização de valor por estágio',
          description:
            'Existem estágios com valor abaixo da média. Considere priorizar itens de maior valor',
        });
      }

      return suggestions;
    },
    getAverageCycleTime() {
      const times = Object.values(this.metrics.avgTimeInStage);
      return times.length > 0
        ? times.reduce((a, b) => a + (b || 0), 0) / times.length
        : 0;
    },
    getWeeklyThroughput() {
      return this.metrics.stageMetrics.itemsCreatedThisWeek;
    },
    getPriorityColor(priority) {
      const colors = {
        low: '#94a3b8',
        medium: '#f59e0b',
        high: '#ef4444',
      };
      return colors[priority] || '#94a3b8';
    },
    getChannelColor(channelName) {
      const colors = {
        site: '#3b82f6',
        telefone: '#22c55e',
        whatsapp: '#a855f7',
        email: '#f59e0b',
        chat: '#ef4444',
        facebook: '#1877f2',
        instagram: '#e4405f',
        linkedin: '#0077b5',
        google: '#4285f4',
        outros: '#94a3b8',
      };
      return colors[channelName.toLowerCase()] || '#94a3b8';
    },
    formatGoalValue(value, goalType, unit) {
      if (value === null || value === undefined || isNaN(value)) {
        return '0';
      }

      switch (goalType) {
        case 'conversion_rate':
        case 'percentage':
          return `${value.toFixed(1)}%`;
        case 'revenue':
          return this.formatCurrency(value);
        case 'items_count':
          return value.toLocaleString();
        default:
          return unit === 'percentage'
            ? `${value.toFixed(1)}%`
            : value.toLocaleString();
      }
    },
    getGoalTypeLabel(goalType) {
      const labels = {
        conversion_rate: 'Taxa de Conversão',
        revenue: 'Receita',
        items_count: 'Quantidade de Itens',
      };
      return labels[goalType] || goalType;
    },
    formatChannelName(channelName) {
      const names = {
        site: 'Site',
        telefone: 'Telefone',
        whatsapp: 'WhatsApp',
        email: 'Email',
        chat: 'Chat',
        facebook: 'Facebook',
        instagram: 'Instagram',
        linkedin: 'LinkedIn',
        google: 'Google',
        outros: 'Outros',
      };
      return (
        names[channelName.toLowerCase()] ||
        channelName.charAt(0).toUpperCase() + channelName.slice(1)
      );
    },
    getStageColor(stageName) {
      // Se contém ":", extrair apenas o nome do stage (parte após os dois pontos)
      const actualStageName = stageName.includes(':')
        ? stageName.split(':')[1].trim()
        : stageName;

      const colors = {
        novo: '#3b82f6',
        contato: '#f59e0b',
        qualificacao: '#8b5cf6',
        proposta: '#06b6d4',
        negociacao: '#f97316',
        fechamento: '#22c55e',
        ganho: '#22c55e',
        perdido: '#ef4444',
        followup: '#84cc16',
        outros: '#94a3b8',
      };
      return colors[actualStageName.toLowerCase()] || '#94a3b8';
    },
    formatStageName(stageName) {
      // Se contém ":", extrair apenas o nome do stage (parte após os dois pontos)
      const actualStageName = stageName.includes(':')
        ? stageName.split(':')[1].trim()
        : stageName;

      const names = {
        novo: 'Novo',
        contato: 'Contato Inicial',
        qualificacao: 'Qualificação',
        proposta: 'Proposta',
        negociacao: 'Negociação',
        fechamento: 'Fechamento',
        ganho: 'Ganho',
        perdido: 'Perdido',
        followup: 'Follow-up',
        outros: 'Outros',
      };
      return (
        names[actualStageName.toLowerCase()] ||
        actualStageName.charAt(0).toUpperCase() + actualStageName.slice(1)
      );
    },
    formatCategoryName(categoryName) {
      const names = {
        premium: 'Serviço Premium',
        basico: 'Serviço Básico',
        consultoria: 'Consultoria',
        digital: 'Produto Digital',
        treinamento: 'Treinamento',
        suporte: 'Suporte',
        desenvolvimento: 'Desenvolvimento',
        outros: 'Outros',
      };
      return (
        names[categoryName.toLowerCase()] ||
        categoryName.charAt(0).toUpperCase() + categoryName.slice(1)
      );
    },
    formatRegionName(regionName) {
      const names = {
        'sao-paulo': 'São Paulo',
        'sao paulo': 'São Paulo',
        'rio-de-janeiro': 'Rio de Janeiro',
        'rio de janeiro': 'Rio de Janeiro',
        'minas-gerais': 'Minas Gerais',
        'minas gerais': 'Minas Gerais',
        parana: 'Paraná',
        'santa-catarina': 'Santa Catarina',
        'rio-grande-do-sul': 'Rio Grande do Sul',
        bahia: 'Bahia',
        pernambuco: 'Pernambuco',
        ceara: 'Ceará',
        goias: 'Goiás',
        'distrito-federal': 'Distrito Federal',
        'distrito federal': 'Distrito Federal',
        outros: 'Outros',
      };
      return (
        names[regionName.toLowerCase()] ||
        regionName.charAt(0).toUpperCase() + regionName.slice(1)
      );
    },
    formatActivityType(type) {
      const typeMap = {
        stage_changed: 'Mudança de Estágio',
        value_changed: 'Alteração de Valor',
        agent_changed: 'Mudança de Agente',
        note_added: 'Nota Adicionada',
        attachment_added: 'Anexo Adicionado',
        checklist_item_added: 'Item de Checklist Adicionado',
        checklist_item_toggled: 'Item de Checklist Alterado',
        conversation_linked: 'Conversa Vinculada',
      };
      return typeMap[type] || type;
    },
    getFunnelNameFromStageKey(stageKey) {
      // Se contém ":", extrair o nome do funil (parte antes dos dois pontos)
      if (stageKey.includes(':')) {
        return stageKey.split(':')[0].trim();
      }
      return null;
    },
  },
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <ReportHeader header-title="Relatórios Kanban">
      <V4Button
        label="Baixar Relatório"
        icon="i-ph-download-simple"
        size="sm"
        @click="downloadReports"
      />
    </ReportHeader>

    <ReportFilterSelector
      :show-funnel-filter="true"
      :show-agents-filter="true"
      :show-inbox-filter="false"
      :show-business-hours-switch="false"
      @filter-change="onFilterChange"
    />

    <!-- Loading State -->
    <div v-if="isLoading" class="flex items-center justify-center py-12">
      <div class="loading-spinner">
        <i class="i-ph-circle-notch text-2xl animate-spin text-blue-500" />
        <span class="ml-3 text-slate-600">Carregando métricas...</span>
      </div>
    </div>

    <!-- Empty State -->
    <div
      v-else-if="
        Object.keys(metrics.itemsByStage || {}).length === 0 &&
        userIds &&
        userIds.length > 0
      "
      class="flex items-center justify-center py-16"
    >
      <div class="text-center">
        <i class="i-ph-user-circle text-6xl text-slate-300 mb-4" />
        <h3 class="text-xl font-medium text-slate-600 mb-2">
          Nenhum item encontrado
        </h3>
        <p class="text-slate-500 mb-2">
          O agente selecionado não possui itens vinculados no período
          selecionado.
        </p>
        <p class="text-sm text-slate-400">
          Tente alterar o filtro de data ou selecionar outro agente.
        </p>
      </div>
    </div>

    <!-- Main Content -->
    <div v-else class="space-y-4">
      <!-- Report Tabs -->
      <div class="tabs-container mb-6">
        <div class="tabs-scroll-wrapper">
          <button
            v-for="tab in reportTabs"
            :key="tab.id"
            class="tab-button flex-shrink-0"
            :class="activeTab === tab.id ? 'tab-active' : 'tab-inactive'"
            @click="activeTab = tab.id"
          >
            {{ tab.label }}
          </button>
        </div>
      </div>

      <!-- Tab Content -->
      <div v-if="activeTab === 'overview'" class="space-y-6">
        <!-- Overview Cards -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <div class="overview-card">
            <div class="overview-card-header">
              <div class="overview-icon-wrapper bg-woot-100 dark:bg-woot-900">
                <i class="i-ph-chart-bar text-woot-700 dark:text-woot-300" />
              </div>
              <div class="overview-trend">
                <i class="i-ph-trending-up text-emerald-500 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">{{ Number(metrics.totalItems) }}</div>
              <div class="overview-label">{{ $t('REPORTS.TOTAL_ITEMS') }}</div>
              <div class="overview-description">
                {{ $t('REPORTS.TOTAL_CARDS_PIPELINE') }}
              </div>
            </div>
          </div>

          <div class="overview-card">
            <div class="overview-card-header">
              <div class="overview-icon-wrapper bg-green-100 dark:bg-green-900">
                <i
                  class="i-ph-currency-circle-dollar text-green-700 dark:text-green-300"
                />
              </div>
              <div class="overview-trend">
                <i class="i-ph-trending-up text-emerald-500 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">
                {{ formatCurrency(metrics.totalValue) }}
              </div>
              <div class="overview-label">{{ $t('REPORTS.TOTAL_VALUE') }}</div>
              <div class="overview-description">
                {{ $t('REPORTS.SUM_ALL_VALUES') }}
              </div>
            </div>
          </div>

          <div class="overview-card">
            <div class="overview-card-header">
              <div
                class="overview-icon-wrapper bg-violet-100 dark:bg-violet-900"
              >
                <i class="i-ph-trend-up text-violet-700 dark:text-violet-300" />
              </div>
              <div class="overview-trend">
                <i class="i-ph-minus text-slate-400 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">
                {{ formatCurrency(metrics.averageValue) }}
              </div>
              <div class="overview-label">
                {{ $t('REPORTS.AVERAGE_VALUE') }}
              </div>
              <div class="overview-description">
                {{ $t('REPORTS.AVERAGE_PER_ITEM') }}
              </div>
            </div>
          </div>

          <div class="overview-card">
            <div class="overview-card-header">
              <div class="overview-icon-wrapper bg-slate-100 dark:bg-slate-900">
                <i class="i-ph-users text-slate-700 dark:text-slate-300" />
              </div>
              <div class="overview-trend">
                <i class="i-ph-trending-up text-emerald-500 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">
                {{ Number(metrics.contactMetrics.totalContacts) }}
              </div>
              <div class="overview-label">{{ $t('REPORTS.CONTACTS') }}</div>
              <div class="overview-description">
                {{ $t('REPORTS.UNIQUE_CLIENTS') }}
              </div>
            </div>
          </div>
        </div>

        <!-- Quick Stats -->
        <div class="space-y-3">
          <h3 class="text-lg font-semibold text-slate-800 dark:text-slate-200">
            {{ $t('REPORTS.QUICK_STATS') }}
          </h3>
          <div class="quick-stats">
            <div class="stat-item">
              <div class="stat-icon">
                <i class="i-ph-check-circle text-emerald-500" />
              </div>
              <div class="stat-content">
                <div class="stat-value">
                  {{
                    formatPercentage(metrics.checklistMetrics.completionRate)
                  }}
                </div>
                <div class="stat-label">
                  {{ $t('REPORTS.CHECKLIST_COMPLETE') }}
                </div>
              </div>
            </div>

            <div class="stat-item">
              <div class="stat-icon">
                <i class="i-ph-clock text-blue-500" />
              </div>
              <div class="stat-content">
                <div class="stat-value">
                  {{
                    Number(
                      metrics.activityMetrics.averageActivitiesPerItem
                    ).toFixed(1)
                  }}
                </div>
                <div class="stat-label">
                  {{ $t('REPORTS.ACTIVITIES_PER_ITEM') }}
                </div>
              </div>
            </div>

            <div class="stat-item">
              <div class="stat-icon">
                <i class="i-ph-chat-circle text-purple-500" />
              </div>
              <div class="stat-content">
                <div class="stat-value">
                  {{
                    Number(
                      metrics.activityMetrics.itemsWithConversations
                    ).toFixed(1)
                  }}
                </div>
                <div class="stat-label">
                  {{ $t('REPORTS.WITH_CONVERSATIONS') }}
                </div>
              </div>
            </div>

            <div class="stat-item">
              <div class="stat-icon">
                <i class="i-ph-calendar text-orange-500" />
              </div>
              <div class="stat-content">
                <div class="stat-value">{{ deadlineCardData.total }}</div>
                <div class="stat-label">{{ $t('REPORTS.WITH_DEADLINE') }}</div>
              </div>
            </div>
          </div>
        </div>

        <!-- Charts and Analytics -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <!-- Stage Distribution -->
          <div
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-100 dark:border-slate-700 p-4"
          >
            <div class="mb-3">
              <h3
                class="text-sm font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
              >
                {{ $t('REPORTS.STAGE_DISTRIBUTION') }}
              </h3>
            </div>
            <div class="space-y-4">
              <div
                v-if="
                  stageDistributionPieData &&
                  stageDistributionPieData.length > 0
                "
              >
                <!-- Horizontal Bar Chart -->
                <div class="space-y-3">
                  <div
                    v-for="segment in stageDistributionPieData"
                    :key="segment.id"
                    class="relative"
                  >
                    <div class="flex items-center justify-between mb-2">
                      <div class="flex items-center gap-2">
                        <div
                          class="w-3 h-3 rounded-full flex-shrink-0"
                          :style="{ backgroundColor: segment.color }"
                        />
                        <span
                          class="text-sm font-medium text-slate-700 dark:text-slate-300 truncate"
                        >
                          {{ segment.label }}
                        </span>
                      </div>
                      <div class="flex items-center gap-2">
                        <span
                          class="text-sm text-slate-600 dark:text-slate-400"
                        >
                          {{ segment.value }}
                        </span>
                        <span
                          class="text-xs text-slate-500 dark:text-slate-400"
                        >
                          ({{
                            (
                              (segment.value / metrics.totalItems) *
                              100
                            ).toFixed(1)
                          }}%)
                        </span>
                      </div>
                    </div>

                    <!-- Horizontal Bar -->
                    <div
                      class="relative h-2 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden"
                    >
                      <div
                        class="h-full rounded-full transition-all duration-500 ease-out"
                        :style="{
                          width: `${(segment.value / metrics.totalItems) * 100}%`,
                          backgroundColor: segment.color,
                        }"
                      />
                    </div>
                  </div>
                </div>
</div>

              <div
                v-else
                class="flex items-center justify-center h-32 text-slate-500"
              >
                <div class="text-center">
                  <i class="i-ph-bar-chart text-4xl mb-2 opacity-50" />
                  <p class="text-sm">{{ $t('REPORTS.NO_DATA_AVAILABLE') }}</p>
                </div>
              </div>
            </div>
          </div>

          <!-- Priority Distribution -->
          <div
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-100 dark:border-slate-700 p-4"
          >
            <div class="mb-3">
              <h3
                class="text-sm font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
              >
                {{ $t('REPORTS.PRIORITY_DISTRIBUTION') }}
              </h3>
            </div>
            <div class="space-y-4">
              <div
                v-if="
                  Object.keys(metrics.stageMetrics?.priorityDistribution || {})
                    .length > 0
                "
              >
                <!-- Horizontal Bar Chart -->
                <div class="space-y-3">
                  <div
                    v-for="(count, priority) in metrics.stageMetrics
                      ?.priorityDistribution || {}"
                    :key="priority"
                    class="relative"
                  >
                    <div class="flex items-center justify-between mb-2">
                      <div class="flex items-center gap-2">
                        <div
                          class="w-3 h-3 rounded-full flex-shrink-0"
                          :style="{
                            backgroundColor: getPriorityColor(priority),
                          }"
                        />
                        <span
                          class="text-sm font-medium text-slate-700 dark:text-slate-300 capitalize"
                        >
                          {{
                            priority === 'low'
                              ? $t('REPORTS.LOW')
                              : priority === 'medium'
                                ? $t('REPORTS.MEDIUM')
                                : $t('REPORTS.HIGH')
                          }}
                        </span>
                      </div>
                      <div class="flex items-center gap-2">
                        <span
                          class="text-sm text-slate-600 dark:text-slate-400"
                        >
                          {{ Number(count).toFixed(1) }}
                        </span>
                        <span
                          class="text-xs text-slate-500 dark:text-slate-400"
                        >
                          ({{
                            metrics.totalItems > 0
                              ? ((count / metrics.totalItems) * 100).toFixed(1)
                              : 0
                          }}%)
                        </span>
                      </div>
                    </div>

                    <!-- Horizontal Bar -->
                    <div
                      class="relative h-2 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden"
                    >
                      <div
                        class="h-full rounded-full transition-all duration-500 ease-out"
                        :style="{
                          width: `${metrics.totalItems > 0 ? (count / metrics.totalItems) * 100 : 0}%`,
                          backgroundColor: getPriorityColor(priority),
                        }"
                      />
                    </div>
                  </div>
                </div>
              </div>
</div>
                v-else
                class="flex items-center justify-center h-32 text-slate-500"
              >
                <div class="text-center">
                  <i class="i-ph-bar-chart text-4xl mb-2 opacity-50" />
                  <p class="text-sm">{{ $t('REPORTS.NO_DATA_AVAILABLE') }}</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Activity Metrics -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <!-- Checklist Metrics -->
          <div class="metric-card">
            <div class="metric-header">
              <h4>{{ $t('REPORTS.CHECKLIST_METRICS') }}</h4>
            </div>
            <div class="metric-body">
              <div class="space-y-3">
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.TOTAL_TASKS')
                  }}</span>
                  <span class="font-semibold">{{
                    Number(metrics.checklistMetrics.totalTasks).toFixed(1)
                  }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.COMPLETED')
                  }}</span>
                  <span class="font-semibold text-green-600">{{
                    Number(metrics.checklistMetrics.completedTasks).toFixed(1)
                  }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.COMPLETION_RATE')
                  }}</span>
                  <span class="font-semibold">{{
                    formatPercentage(metrics.checklistMetrics.completionRate)
                  }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Activity Metrics -->
          <div class="metric-card">
            <div class="metric-header">
              <h4>{{ $t('REPORTS.ACTIVITY_METRICS') }}</h4>
            </div>
            <div class="metric-body">
              <div class="space-y-3">
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.TOTAL_ACTIVITIES')
                  }}</span>
                  <span class="font-semibold">{{
                    Number(metrics.activityMetrics.totalActivities).toFixed(1)
                  }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.AVERAGE_PER_ITEM')
                  }}</span>
                  <span class="font-semibold">{{
                    Number(
                      metrics.activityMetrics.averageActivitiesPerItem
                    ).toFixed(1)
                  }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.WITH_CONVERSATIONS')
                  }}</span>
                  <span class="font-semibold">{{
                    Number(
                      metrics.activityMetrics.itemsWithConversations
                    ).toFixed(1)
                  }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Offer Ranges -->
          <div class="metric-card">
            <div class="metric-header">
              <h4>{{ $t('REPORTS.OFFER_RANGES') }}</h4>
            </div>
            <div class="metric-body">
              <div class="space-y-3">
                <div class="offer-range">
                  <div class="flex justify-between text-xs mb-1">
                    <span>{{ $t('REPORTS.UP_TO_1000') }}</span>
                    <span class="font-medium">{{
                      metrics.stageMetrics.offerRanges.low
                    }}</span>
                  </div>
                  <div
                    class="h-1.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden"
                  >
                    <div
                      class="h-full bg-emerald-400 rounded-full transition-all duration-500"
                      :style="{
                        width: `${(metrics.stageMetrics.offerRanges.low / metrics.stageMetrics.totalOffers) * 100}%`,
                      }"
                    />
                  </div>
                </div>
                <div class="offer-range">
                  <div class="flex justify-between text-xs mb-1">
                    <span>{{ $t('REPORTS.FROM_1001_TO_5000') }}</span>
                    <span class="font-medium">{{
                      metrics.stageMetrics.offerRanges.medium
                    }}</span>
                  </div>
                  <div
                    class="h-1.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden"
                  >
                    <div
                      class="h-full bg-emerald-500 rounded-full transition-all duration-500"
                      :style="{
                        width: `${(metrics.stageMetrics.offerRanges.medium / metrics.stageMetrics.totalOffers) * 100}%`,
                      }"
                    />
                  </div>
                </div>
                <div class="offer-range">
                  <div class="flex justify-between text-xs mb-1">
                    <span>{{ $t('REPORTS.ABOVE_5000') }}</span>
                    <span class="font-medium">{{
                      metrics.stageMetrics.offerRanges.high
                    }}</span>
                  </div>
                  <div
                    class="h-1.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden"
                  >
                    <div
                      class="h-full bg-emerald-600 rounded-full transition-all duration-500"
                      :style="{
                        width: `${(metrics.stageMetrics.offerRanges.high / metrics.stageMetrics.totalOffers) * 100}%`,
                      }"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Productivity Tab -->
      <div v-if="activeTab === 'productivity'" class="space-y-6">
        <!-- Productivity Overview Cards -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <div class="overview-card">
            <div class="overview-card-header">
              <div
                class="overview-icon-wrapper"
                style="
                  background-color: #dcfce7;
                  --tw-ring-color: rgb(16 185 129 / var(--tw-ring-opacity));
                "
              >
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
                  style="color: #047857"
                >
                  <circle cx="12" cy="12" r="10" />
                  <line x1="22" x2="18" y1="12" y2="12" />
                  <line x1="6" x2="2" y1="12" y2="12" />
                  <line x1="12" x2="12" y1="6" y2="2" />
                  <line x1="12" x2="12" y1="22" y2="18" />
                </svg>
              </div>
              <div class="overview-trend">
                <i class="i-ph-trending-up text-emerald-500 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">
                {{ formatPercentage(productivityMetrics.conversionRate) }}
              </div>
              <div class="overview-label">
                {{ $t('REPORTS.CONVERSION_RATE') }}
              </div>
              <div class="overview-description">
                {{ $t('REPORTS.WON_DEALS_VS_TOTAL') }}
              </div>
            </div>
          </div>

          <div class="overview-card">
            <div class="overview-card-header">
              <div class="overview-icon-wrapper bg-green-100 dark:bg-green-900">
                <i
                  class="i-ph-currency-circle-dollar text-green-700 dark:text-green-300"
                />
              </div>
              <div class="overview-trend">
                <i class="i-ph-trending-up text-emerald-500 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">
                {{ formatCurrency(productivityMetrics.averageTicketWon) }}
              </div>
              <div class="overview-label">
                {{ $t('REPORTS.AVERAGE_WON_TICKET') }}
              </div>
              <div class="overview-description">
                {{ $t('REPORTS.AVERAGE_CLOSED_DEALS') }}
              </div>
            </div>
          </div>

          <div class="overview-card">
            <div class="overview-card-header">
              <div class="overview-icon-wrapper bg-red-100 dark:bg-red-900">
                <i class="i-ph-trend-down text-red-700 dark:text-red-300" />
              </div>
              <div class="overview-trend">
                <i class="i-ph-minus text-slate-400 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">
                {{ formatCurrency(productivityMetrics.totalValueLost) }}
              </div>
              <div class="overview-label">
                {{ $t('REPORTS.TOTAL_VALUE_LOST') }}
              </div>
              <div class="overview-description">
                {{ $t('REPORTS.SUM_LOST_DEALS') }}
              </div>
            </div>
          </div>

          <div class="overview-card">
            <div class="overview-card-header">
              <div
                class="overview-icon-wrapper"
                style="background-color: #faf5ff"
              >
                <i class="i-ph-clock" style="color: #7c3aed" />
              </div>
              <div class="overview-trend">
                <i class="i-ph-trending-down text-emerald-500 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">
                {{
                  Math.round(productivityMetrics.cycleAnalysis.averageCycle)
                }}
                {{ $t('REPORTS.DAYS') }}
              </div>
              <div class="overview-label">{{ $t('REPORTS.SALES_CYCLE') }}</div>
              <div class="overview-description">
                {{ $t('REPORTS.AVERAGE_TIME_CLOSE_DEAL') }}
              </div>
            </div>
          </div>
        </div>

        <!-- Productivity Metrics Cards -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <!-- Checklist Status Metrics -->
          <div class="metric-card">
            <div class="metric-header">
              <i class="i-ph-check-square text-blue-500" />
              <h4>{{ $t('REPORTS.CHECKLIST_METRICS') }}</h4>
            </div>
            <div class="metric-body">
              <div class="space-y-3">
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.OPEN_ITEMS')
                  }}</span>
                  <span class="font-semibold">{{
                    productivityMetrics.checklistMetrics.openItems
                  }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.WON_ITEMS')
                  }}</span>
                  <span class="font-semibold text-green-600">{{
                    productivityMetrics.checklistMetrics.wonItems
                  }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.LOST_ITEMS')
                  }}</span>
                  <span class="font-semibold text-red-600">{{
                    productivityMetrics.checklistMetrics.lostItems
                  }}</span>
                </div>
                <div
                  class="flex justify-between border-t border-slate-100 dark:border-slate-700 pt-2"
                >
                  <span
                    class="text-sm font-medium text-slate-700 dark:text-slate-300"
                    >{{ $t('REPORTS.TOTAL_ITEMS_LABEL') }}</span>
                  <span class="font-bold text-slate-900 dark:text-white">{{
                    productivityMetrics.checklistMetrics.totalItems
                  }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Activity Types Metrics -->
          <div class="metric-card">
            <div class="metric-header">
              <i class="i-ph-activity text-purple-500" />
              <h4>{{ $t('REPORTS.ACTIVITY_METRICS') }}</h4>
            </div>
            <div class="metric-body">
              <div class="space-y-3">
                <div
                  v-for="(count, type) in productivityMetrics.activityMetrics
                    .byType"
                  :key="type"
                  class="flex justify-between"
                >
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    formatActivityType(type)
                  }}</span>
                  <span class="font-semibold">{{ Number(count) }}</span>
                </div>
                <div
                  class="flex justify-between border-t border-slate-100 dark:border-slate-700 pt-2"
                >
                  <span
                    class="text-sm font-medium text-slate-700 dark:text-slate-300"
                    >{{ $t('REPORTS.TOTAL_ACTIVITIES') }}</span>
                  <span class="font-bold text-slate-900 dark:text-white">{{
                    Number(productivityMetrics.activityMetrics.total)
                  }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Offers Metrics -->
          <div class="metric-card">
            <div class="metric-header">
              <i class="i-ph-hand-heart text-green-500" />
              <h4>{{ $t('REPORTS.OFFER_RANGES') }}</h4>
            </div>
            <div class="metric-body">
              <div class="space-y-3">
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.WITH_CONVERSATIONS')
                  }}</span>
                  <span class="font-semibold">{{
                    productivityMetrics.offersMetrics.itemsWithOffers
                  }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.AVERAGE_PER_ITEM')
                  }}</span>
                  <span class="font-semibold text-green-600">{{
                    formatCurrency(
                      productivityMetrics.offersMetrics.averageOfferValue
                    )
                  }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-sm text-slate-600 dark:text-slate-400">{{
                    $t('REPORTS.TOTAL_OFFERS')
                  }}</span>
                  <span class="font-semibold">{{
                    productivityMetrics.offersMetrics.totalOffers
                  }}</span>
                </div>
                <div
                  class="flex justify-between border-t border-slate-100 dark:border-slate-700 pt-2"
                >
                  <span
                    class="text-sm font-medium text-slate-700 dark:text-slate-300"
                    >{{ $t('REPORTS.PERCENTAGE_WITH_OFFERS') }}</span>
                  <span class="font-bold text-slate-900 dark:text-white">{{
                      productivityMetrics.offersMetrics.percentageWithOffers
                    }}%</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Additional Productivity Insights -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <!-- Sales Performance Chart -->
          <div
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-100 dark:border-slate-700 p-4"
          >
            <div class="mb-3">
              <h3
                class="text-sm font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
              >
                {{ $t('REPORTS.SALES_PERFORMANCE') }}
              </h3>
            </div>
            <div class="space-y-4">
              <div class="space-y-3">
                <div
                  class="flex items-center justify-between p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg"
                >
                  <div class="flex items-center gap-2">
                    <div class="w-3 h-3 rounded-full bg-green-500" />
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                      >{{ $t('REPORTS.WON_DEALS') }}</span>
                  </div>
                  <div class="text-right">
                    <div
                      class="text-sm font-semibold text-slate-900 dark:text-white"
                    >
                      {{ productivityMetrics.salesPerformance.won }}
                    </div>
                    <div class="text-xs text-slate-500 dark:text-slate-400">
                      {{ productivityMetrics.salesPerformance.wonPercentage }}%
                    </div>
                  </div>
                </div>
                <div
                  class="flex items-center justify-between p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg"
                >
                  <div class="flex items-center gap-2">
                    <div class="w-3 h-3 rounded-full bg-red-500" />
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                      >{{ $t('REPORTS.LOST_DEALS') }}</span>
                  </div>
                  <div class="text-right">
                    <div
                      class="text-sm font-semibold text-slate-900 dark:text-white"
                    >
                      {{ productivityMetrics.salesPerformance.lost }}
                    </div>
                    <div class="text-xs text-slate-500 dark:text-slate-400">
                      {{ productivityMetrics.salesPerformance.lostPercentage }}%
                    </div>
                  </div>
                </div>
                <div
                  class="flex items-center justify-between p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg"
                >
                  <div class="flex items-center gap-2">
                    <div class="w-3 h-3 rounded-full bg-yellow-500" />
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                      >{{ $t('REPORTS.IN_PROGRESS') }}</span>
                  </div>
                  <div class="text-right">
                    <div
                      class="text-sm font-semibold text-slate-900 dark:text-white"
                    >
                      {{ productivityMetrics.salesPerformance.open }}
                    </div>
                    <div class="text-xs text-slate-500 dark:text-slate-400">
                      {{ productivityMetrics.salesPerformance.openPercentage }}%
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Cycle Time Analysis -->
          <div
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-100 dark:border-slate-700 p-4"
          >
            <div class="mb-3">
              <h3
                class="text-sm font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
              >
                {{ $t('REPORTS.CYCLE_ANALYSIS') }}
              </h3>
            </div>
            <div class="space-y-4">
              <div class="space-y-3">
                <div
                  class="flex items-center justify-between p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg"
                >
                  <div class="flex items-center gap-2">
                    <i class="i-ph-clock text-blue-500" />
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                      >{{ $t('REPORTS.AVERAGE_CYCLE') }}</span>
                  </div>
                  <div class="text-right">
                    <div
                      class="text-sm font-semibold text-slate-900 dark:text-white"
                    >
                      {{
                        Math.round(
                          productivityMetrics.cycleAnalysis.averageCycle
                        )
                      }}
                      {{ $t('REPORTS.DAYS') }}
                    </div>
                    <div class="text-xs text-slate-500 dark:text-slate-400">
                      {{ $t('REPORTS.SINCE_CREATION_TO_WON') }}
                    </div>
                  </div>
                </div>
                <div
                  class="flex items-center justify-between p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg"
                >
                  <div class="flex items-center gap-2">
                    <i class="i-ph-trending-up text-green-500" />
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                      >{{ $t('REPORTS.BEST_CYCLE') }}</span>
                  </div>
                  <div class="text-right">
                    <div
                      class="text-sm font-semibold text-slate-900 dark:text-white"
                    >
                      {{
                        Math.round(productivityMetrics.cycleAnalysis.bestCycle)
                      }}
                      {{ $t('REPORTS.DAYS') }}
                    </div>
                    <div class="text-xs text-slate-500 dark:text-slate-400">
                      {{ $t('REPORTS.FASTEST_DEAL') }}
                    </div>
                  </div>
                </div>
                <div
                  class="flex items-center justify-between p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg"
                >
                  <div class="flex items-center gap-2">
                    <i class="i-ph-trending-down text-red-500" />
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                      >{{ $t('REPORTS.WORST_CYCLE') }}</span>
                  </div>
                  <div class="text-right">
                    <div
                      class="text-sm font-semibold text-slate-900 dark:text-white"
                    >
                      {{
                        Math.round(productivityMetrics.cycleAnalysis.worstCycle)
                      }}
                      {{ $t('REPORTS.DAYS') }}
                    </div>
                    <div class="text-xs text-slate-500 dark:text-slate-400">
                      {{ $t('REPORTS.SLOWEST_DEAL') }}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Sales Tab -->
      <div v-if="activeTab === 'sales'" class="space-y-6">
        <!-- Sales Overview Cards -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <div class="overview-card">
            <div class="overview-card-header">
              <div
                class="overview-icon-wrapper"
                style="background-color: #dcfce7"
              >
                <i class="i-ph-currency-circle-dollar" style="color: #047857" />
              </div>
              <div class="overview-trend">
                <i class="i-ph-trending-up text-emerald-500 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">
                {{ formatCurrency(salesMetrics.totalRevenue) }}
              </div>
              <div class="overview-label">
                {{ $t('REPORTS.TOTAL_REVENUE') }}
              </div>
              <div class="overview-description">
                {{ $t('REPORTS.SALES_MADE_IN_PERIOD') }}
              </div>
            </div>
          </div>

          <div class="overview-card">
            <div class="overview-card-header">
              <div
                class="overview-icon-wrapper"
                style="background-color: #dbeafe"
              >
                <i class="i-ph-target" style="color: #1d4ed8" />
              </div>
              <div class="overview-trend">
                <i class="i-ph-trending-up text-emerald-500 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">
                {{ formatPercentage(productivityMetrics.conversionRate) }}
              </div>
              <div class="overview-label">
                {{ $t('REPORTS.CONVERSION_RATE') }}
              </div>
              <div class="overview-description">
                {{ $t('REPORTS.PROSPECTING_TO_CLOSED_SALE') }}
              </div>
            </div>
          </div>

          <div class="overview-card">
            <div class="overview-card-header">
              <div
                class="overview-icon-wrapper"
                style="background-color: #faf5ff"
              >
                <i class="i-ph-currency-circle-dollar" style="color: #7c3aed" />
              </div>
              <div class="overview-trend">
                <i class="i-ph-minus text-slate-400 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">
                {{ formatCurrency(salesMetrics.averageTicket) }}
              </div>
              <div class="overview-label">
                {{ $t('REPORTS.AVERAGE_TICKET') }}
              </div>
              <div class="overview-description">
                {{ $t('REPORTS.AVERAGE_VALUE_PER_SALE') }}
              </div>
            </div>
          </div>

          <div class="overview-card">
            <div class="overview-card-header">
              <div
                class="overview-icon-wrapper"
                style="background-color: #fff7ed"
              >
                <i class="i-ph-shopping-cart" style="color: #c2410c" />
              </div>
              <div class="overview-trend">
                <i class="i-ph-trending-up text-emerald-500 text-sm" />
              </div>
            </div>
            <div class="overview-card-content">
              <div class="overview-value">
                {{ Number(salesMetrics.closedDeals) }}
              </div>
              <div class="overview-label">{{ $t('REPORTS.CLOSED_DEALS') }}</div>
              <div class="overview-description">
                {{ $t('REPORTS.SUCCESSFULLY_FINISHED_DEALS') }}
              </div>
            </div>
          </div>
        </div>

        <!-- Sales Performance Metrics -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <!-- Sales by Channel -->
          <div
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-100 dark:border-slate-700 p-4"
          >
            <div class="mb-3">
              <h3
                class="text-sm font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
              >
                {{ $t('REPORTS.SALES_BY_CHANNEL') }}
              </h3>
            </div>
            <div class="space-y-4">
              <div class="space-y-3">
                <div
                  v-for="(
                    channelData, channelName
                  ) in salesMetrics.salesByChannel"
                  :key="channelName"
                  class="flex items-center justify-between p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg"
                >
                  <div class="flex items-center gap-2">
                    <div
                      class="w-3 h-3 rounded-full"
                      :style="{ backgroundColor: getChannelColor(channelName) }"
                    />
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300 capitalize"
                      >{{ formatChannelName(channelName) }}</span>
                  </div>
                  <div class="text-right">
                    <div
                      class="text-sm font-semibold text-slate-900 dark:text-white"
                    >
                      {{ formatCurrency(channelData.value || 0) }}
                    </div>
                    <div class="text-xs text-slate-500 dark:text-slate-400">
                      {{ Number(channelData.count || 0).toFixed(1) }}
                      {{ $t('REPORTS.SALES') }}
                    </div>
                  </div>
                </div>
                <div
                  v-if="
                    !salesMetrics.salesByChannel ||
                    Object.keys(salesMetrics.salesByChannel).length === 0
                  "
                  class="text-center py-4 text-slate-500"
                >
                  <p class="text-sm">
                    {{ $t('REPORTS.NO_CHANNEL_DATA_AVAILABLE') }}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <!-- Sales Funnel Efficiency -->
          <div
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-100 dark:border-slate-700 p-4"
          >
            <div class="mb-3">
              <h3
                class="text-sm font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
              >
                {{ $t('REPORTS.FUNNEL_EFFICIENCY') }}
              </h3>
            </div>
            <div class="space-y-4">
              <div class="space-y-3">
                <!-- Initial stage (Prospecção) -->
                <div
                  class="flex items-center justify-between p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg"
                >
                  <div class="flex items-center gap-2">
                    <div class="w-3 h-3 rounded-full bg-slate-400" />
                    <span
                      class="text-sm font-medium text-slate-700 dark:text-slate-300"
                      >{{ $t('REPORTS.PROSPECTING') }}</span>
                  </div>
                  <div class="text-right">
                    <div
                      class="text-sm font-semibold text-slate-900 dark:text-white"
                    >
                      {{ metrics.totalItems }}
                    </div>
                    <div class="text-xs text-slate-500 dark:text-slate-400">
                      100% {{ $t('REPORTS.OF_TOTAL') }}
                    </div>
                  </div>
                </div>
                <!-- Dynamic stages from funnel efficiency -->
                <div
                  v-for="(
                    stageData, stageName
                  ) in salesMetrics.funnelEfficiency"
                  :key="stageName"
                  class="flex items-center justify-between p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg"
                >
                  <div class="flex items-center gap-2">
                    <div
                      class="w-3 h-3 rounded-full"
                      :style="{ backgroundColor: getStageColor(stageName) }"
                    />
                    <div class="flex items-center gap-2">
                      <span
                        class="text-sm font-medium text-slate-700 dark:text-slate-300 capitalize"
                        >{{ formatStageName(stageName) }}</span>
                      <span
                        v-if="
                          isAllFunnelsFilter &&
                          getFunnelNameFromStageKey(stageName)
                        "
                        class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium"
                        style="background-color: #e0f2fe; color: #0369a1"
                      >
                        {{ getFunnelNameFromStageKey(stageName) }}
                      </span>
                    </div>
                  </div>
                  <div class="text-right">
                    <div
                      class="text-sm font-semibold text-slate-900 dark:text-white"
                    >
                      {{ Number(stageData.count) }}
                    </div>
                    <div class="text-xs text-slate-500 dark:text-slate-400">
                      {{ stageData.conversion_rate }}%
                      {{ $t('REPORTS.CONVERSION') }}
                    </div>
                  </div>
                </div>
                <div
                  v-if="
                    !salesMetrics.funnelEfficiency ||
                    Object.keys(salesMetrics.funnelEfficiency).length === 0
                  "
                  class="text-center py-4 text-slate-500"
                >
                  <p class="text-sm">
                    {{ $t('REPORTS.NO_FUNNEL_EFFICIENCY_DATA') }}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Sales Analytics -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <!-- Top Products/Services -->
          <div class="metric-card">
            <div class="metric-header">
              <i class="i-ph-package text-blue-500" />
              <h4>{{ $t('REPORTS.TOP_PRODUCTS_SERVICES') }}</h4>
            </div>
            <div class="metric-body">
              <div class="space-y-3">
                <div
                  v-for="(
                    categoryData, categoryName, index
                  ) in sortedTopCategories.slice(0, 3)"
                  :key="categoryName"
                  class="flex justify-between"
                >
                  <span
                    class="text-sm text-slate-600 dark:text-slate-400 capitalize"
                    >{{ formatCategoryName(categoryName) }}</span>
                  <span class="font-semibold">{{
                    formatCurrency(categoryData.value || 0)
                  }}</span>
                </div>
                <div
                  v-if="remainingCategoriesValue > 0"
                  class="flex justify-between border-t border-slate-100 dark:border-slate-700 pt-2"
                >
                  <span
                    class="text-sm font-medium text-slate-700 dark:text-slate-300"
                    >{{ $t('REPORTS.OTHERS') }}</span>
                  <span class="font-bold text-slate-900 dark:text-white">{{
                    formatCurrency(remainingCategoriesValue)
                  }}</span>
                </div>
                <div
                  v-if="
                    !salesMetrics.salesByCategory ||
                    Object.keys(salesMetrics.salesByCategory).length === 0
                  "
                  class="text-center py-4 text-slate-500"
                >
                  <p class="text-sm">
                    {{ $t('REPORTS.NO_CATEGORY_DATA_AVAILABLE') }}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <!-- Sales by Region -->
          <div class="metric-card">
            <div class="metric-header">
              <i class="i-ph-map-pin text-green-500" />
              <h4>{{ $t('REPORTS.SALES_BY_REGION') }}</h4>
            </div>
            <div class="metric-body">
              <div class="space-y-3">
                <div
                  v-for="(
                    regionData, regionName, index
                  ) in sortedTopRegions.slice(0, 3)"
                  :key="regionName"
                  class="flex justify-between"
                >
                  <span
                    class="text-sm text-slate-600 dark:text-slate-400 capitalize"
                    >{{ formatRegionName(regionName) }}</span>
                  <span class="font-semibold">{{
                    formatCurrency(regionData.value || 0)
                  }}</span>
                </div>
                <div
                  v-if="remainingRegionsValue > 0"
                  class="flex justify-between border-t border-slate-100 dark:border-slate-700 pt-2"
                >
                  <span
                    class="text-sm font-medium text-slate-700 dark:text-slate-300"
                    >{{ $t('REPORTS.OTHER_REGIONS') }}</span>
                  <span class="font-bold text-slate-900 dark:text-white">{{
                    formatCurrency(remainingRegionsValue)
                  }}</span>
                </div>
                <div
                  v-if="
                    !salesMetrics.salesByRegion ||
                    Object.keys(salesMetrics.salesByRegion).length === 0
                  "
                  class="text-center py-4 text-slate-500"
                >
                  <p class="text-sm">
                    {{ $t('REPORTS.NO_REGION_DATA_AVAILABLE') }}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <!-- Monthly Goal -->
          <div class="metric-card">
            <div class="metric-header">
              <i class="i-ph-target text-purple-500" />
              <h4>{{ $t('REPORTS.MONTHLY_GOAL') }}</h4>
            </div>
            <div class="metric-body">
              <div v-if="monthlyGoalFromFunnel.goalType" class="space-y-3">
                <div class="text-center">
                  <div
                    class="metric-value-large"
                    :class="
                      monthlyGoalFromFunnel.percentage >= 100
                        ? 'text-green-600'
                        : 'text-red-600'
                    "
                  >
                    {{
                      formatGoalValue(
                        monthlyGoalFromFunnel.achieved,
                        monthlyGoalFromFunnel.goalType,
                        monthlyGoalFromFunnel.unit
                      )
                    }}
                  </div>
                  <div class="metric-subtext">
                    {{
                      monthlyGoalFromFunnel.percentage >= 100
                        ? $t('REPORTS.GOAL_ACHIEVED')
                        : $t('REPORTS.GOAL_NOT_ACHIEVED')
                    }}
                  </div>
                  <div class="text-xs text-slate-500 dark:text-slate-400 mt-1">
                    {{ getGoalTypeLabel(monthlyGoalFromFunnel.goalType) }}
                  </div>
                </div>
                <div class="space-y-2">
                  <div class="flex justify-between text-sm">
                    <span class="text-slate-600 dark:text-slate-400">{{
                      $t('REPORTS.ACHIEVED')
                    }}</span>
                    <span
                      class="font-semibold"
                      :class="
                        monthlyGoalFromFunnel.percentage >= 100
                          ? 'text-green-600'
                          : 'text-red-600'
                      "
                    >
                      {{
                        formatGoalValue(
                          monthlyGoalFromFunnel.achieved,
                          monthlyGoalFromFunnel.goalType,
                          monthlyGoalFromFunnel.unit
                        )
                      }}
                    </span>
                  </div>
                  <div
                    class="h-2 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden"
                  >
                    <div
                      class="h-full rounded-full transition-all duration-500"
                      :class="
                        monthlyGoalFromFunnel.percentage >= 100
                          ? 'bg-green-500'
                          : 'bg-red-500'
                      "
                      :style="{
                        width:
                          Math.min(monthlyGoalFromFunnel.percentage, 100) + '%',
                      }"
                    />
                  </div>
                  <div class="flex justify-between text-sm">
                    <span class="text-slate-600 dark:text-slate-400">{{
                      $t('REPORTS.GOAL')
                    }}</span>
                    <span class="font-semibold">{{
                      formatGoalValue(
                        monthlyGoalFromFunnel.target,
                        monthlyGoalFromFunnel.goalType,
                        monthlyGoalFromFunnel.unit
                      )
                    }}</span>
                  </div>
                </div>
                <div
                  class="text-center pt-2 border-t border-slate-100 dark:border-slate-700"
                >
                  <div
                    class="text-xs font-medium"
                    :class="
                      monthlyGoalFromFunnel.percentage >= 100
                        ? 'text-emerald-600'
                        : 'text-red-600'
                    "
                  >
                    {{
                      monthlyGoalFromFunnel.percentage >= 100
                        ? `${$t('REPORTS.GOAL_EXCEEDED_BY')} ${(monthlyGoalFromFunnel.percentage - 100).toFixed(1)}%`
                        : `${$t('REPORTS.MISSING_TO_ACHIEVE_GOAL')} ${(100 - monthlyGoalFromFunnel.percentage).toFixed(1)}%`
                    }}
                  </div>
                </div>
              </div>
              <div v-else class="text-center py-4 text-slate-500">
                <p class="text-sm">
                  {{ $t('REPORTS.NO_GOAL_DEFINED_FOR_FUNNEL') }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Overview Cards - Modern Design */
.overview-card {
  @apply bg-white dark:bg-slate-800 rounded-2xl shadow-sm border border-slate-100 dark:border-slate-700 p-4 relative overflow-hidden;
}

.overview-card-header {
  @apply flex items-center justify-between mb-3;
}

.overview-icon-wrapper {
  @apply flex items-center justify-center w-8 h-8 rounded-lg;
}

.overview-trend {
  @apply opacity-60;
}

.overview-card-content {
  @apply text-left;
}

.overview-value {
  @apply text-2xl font-bold text-slate-900 dark:text-white mb-1 leading-none;
}

.overview-label {
  @apply text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1 uppercase tracking-wide;
}

.overview-description {
  @apply text-xs text-slate-500 dark:text-slate-400 leading-relaxed;
}

/* Quick Stats */
.quick-stats {
  @apply grid grid-cols-2 md:grid-cols-4 gap-4 p-4 bg-slate-50 dark:bg-slate-800/50 rounded-xl border border-slate-100 dark:border-slate-700;
}

.stat-item {
  @apply flex items-center gap-3 p-3 bg-white dark:bg-slate-800 rounded-lg border border-slate-100 dark:border-slate-700 transition-all duration-200 hover:shadow-sm;
}

.stat-icon {
  @apply flex items-center justify-center w-8 h-8 rounded-lg bg-slate-100 dark:bg-slate-700;
}

.stat-icon i {
  @apply text-sm;
}

.stat-content {
  @apply flex-1;
}

.stat-value {
  @apply text-lg font-bold text-slate-900 dark:text-white leading-none;
}

.stat-label {
  @apply text-xs text-slate-500 dark:text-slate-400 font-medium uppercase tracking-wide;
}

/* Chart Cards */
.chart-card {
  @apply bg-white dark:bg-slate-800 rounded-xl shadow-sm border border-slate-100 dark:border-slate-700 overflow-hidden transition-all duration-200 hover:shadow-md;
}

.chart-header {
  @apply flex items-center gap-3 p-4 border-b border-slate-100 dark:border-slate-700 bg-slate-50/50 dark:bg-slate-800/50;
}

.chart-header i {
  @apply text-lg;
}

.chart-header h3 {
  @apply text-base font-semibold text-slate-700 dark:text-slate-200;
}

.chart-body {
  @apply p-4;
}

.priority-item {
  @apply transition-all duration-200;
}

/* Detailed Metric Cards */
.metric-card {
  @apply bg-white dark:bg-slate-800 rounded-xl border border-slate-100 dark:border-slate-700 p-4 transition-all duration-200 hover:shadow-md;
}

.metric-header {
  @apply flex items-center gap-2 mb-3;
}

.metric-header i {
  @apply text-lg;
}

.metric-header h4 {
  @apply text-sm font-semibold text-slate-700 dark:text-slate-200;
}

.metric-body {
  @apply space-y-3;
}

.metric-value-large {
  @apply text-3xl font-bold text-slate-900 dark:text-white mb-1;
}

.metric-subtext {
  @apply text-xs text-slate-500 dark:text-slate-400;
}

/* Offer Ranges */
.offer-range {
  @apply transition-all duration-200;
}

/* Legacy support */
.report-card {
  @apply bg-white dark:bg-slate-800 rounded-lg shadow-sm transition-all duration-200 hover:shadow-md border border-slate-100 dark:border-slate-700 overflow-hidden;
}

.card-header {
  @apply p-4 border-b border-slate-100 dark:border-slate-700;
}

.card-header h3 {
  @apply text-base font-medium text-slate-700 dark:text-slate-200;
}

.card-body {
  @apply p-4;
}

.metric-summary-card {
  @apply bg-slate-50 dark:bg-slate-700 rounded-lg p-3 flex flex-col items-center transition-all duration-200;
}

.metric-summary-card .metric-label {
  @apply text-xs text-slate-500 dark:text-slate-400 mb-1 text-center;
}

.metric-summary-card .metric-value {
  @apply text-lg font-semibold text-slate-900 dark:text-white;
}

.priority-bar,
.offer-range-bar {
  @apply transition-all duration-200;
}

.loading-spinner {
  @apply flex items-center justify-center;
}

/* Report Tabs Styles */
.tabs-container {
  margin-bottom: 1rem;
}

.tab-button.tab-active {
  @apply text-woot-500;
}

.tab-button.tab-active::after {
  content: '';
  @apply absolute bottom-0 left-0 right-0 h-0.5 bg-woot-500;
}

.tab-button.tab-inactive {
  @apply text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-100;
}

.tab-inactive:hover {
  color: #64748b;
}

.dark .tab-inactive {
  color: #94a3b8;
}

.dark .tab-inactive:hover {
  color: #64748b;
}

/* Estilos para as abas com scroll lateral */
.tabs-container {
  overflow: hidden;
}

.tabs-scroll-wrapper {
  display: flex;
  overflow-x: auto;
  scrollbar-width: none; /* Firefox */
  -ms-overflow-style: none; /* IE and Edge */
  scroll-behavior: smooth;
}

.tabs-scroll-wrapper::-webkit-scrollbar {
  display: none; /* Chrome, Safari and Opera */
}

.tab-button {
  @apply px-4 py-2 text-sm font-medium relative transition-colors whitespace-nowrap;
}

/* Mobile: ajustes específicos para abas */
@media (max-width: 768px) {
  .tab-button {
    @apply px-3 py-2 text-xs;
  }

  .tabs-scroll-wrapper {
    padding-bottom: 2px; /* Espaço para o scroll */
  }
}
</style>
