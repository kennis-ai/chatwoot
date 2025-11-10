<script setup>
/* global axios */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

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
const emit = defineEmits([
  'update:item',
  'item-updated'
]);

const { t } = useI18n();

// Computed properties para atividades
const activities = computed(() => {
  return props.item?.activities || [];
});

// Helper functions para buscar dados
const findNoteByActivity = (activity) => {
  const notes = props.item?.item_details?.notes;
  if (!Array.isArray(notes)) return null;
  return notes.find(note =>
    new Date(note.created_at).getTime() === new Date(activity.created_at).getTime()
  );
};

const findChecklistItemByActivity = (activity) => {
  const checklist = props.item?.item_details?.checklist;
  if (!Array.isArray(checklist)) return null;
  return checklist.find(item =>
    new Date(item.created_at).getTime() === new Date(activity.created_at).getTime()
  );
};

const findAttachmentByActivity = (activity) => {
  const attachments = props.item?.item_details?.attachments;
  if (!Array.isArray(attachments)) return null;
  return attachments.find(att =>
    new Date(att.created_at).getTime() === new Date(activity.created_at).getTime()
  );
};

const getStageName = (stageId) => {
  if (!stageId) return '-';

  const stages = props.item?.item_details?.funnel?.stages;
  if (!stages || typeof stages !== 'object') return stageId;

  const stageName = stages[stageId]?.name;
  return stageName || stageId;
};

const history = computed(() => {
  return activities.value
    .map(activity => {
      let icon, title, details;

      switch (activity.type) {
        case 'attachment_added':
          icon = 'attach';
          title = t('KANBAN.HISTORY.ATTACHMENT_ADDED');
          const attachment = findAttachmentByActivity(activity);
          details = attachment
            ? `${attachment.filename} (${(attachment.byte_size / 1024).toFixed(1)} KB)`
            : `${t('KANBAN.HISTORY.FILE')}: ${activity.details.filename || 'Arquivo'}`;
          break;

        case 'note_added':
          icon = 'comment-add';
          title = t('KANBAN.HISTORY.NOTE_ADDED');
          const note = findNoteByActivity(activity);
          details = note ? note.text : activity.details.note_text || 'Nota adicionada';
          break;

        case 'checklist_item_added':
          icon = 'add-circle';
          title = t('KANBAN.HISTORY.CHECKLIST_ITEM_ADDED');
          const checklistItem = findChecklistItemByActivity(activity);
          details = checklistItem ? checklistItem.text : activity.details.item_text || 'Item adicionado';
          break;

        case 'checklist_item_toggled':
          icon = activity.details.completed ? 'checkmark' : 'dismiss';
          title = t('KANBAN.HISTORY.CHECKLIST_ITEM_UPDATED');
          const toggledItem = findChecklistItemByActivity(activity);
          const itemText = toggledItem ? toggledItem.text : activity.details.item_text || 'Item';
          details = `${itemText} - ${
            activity.details.completed
              ? t('KANBAN.HISTORY.COMPLETED')
              : t('KANBAN.HISTORY.PENDING')
          }`;
          break;

        case 'priority_changed':
          icon = 'alert';
          title = t('KANBAN.HISTORY.PRIORITY_CHANGED');
          details = `${
            activity.details.old_priority || t('KANBAN.HISTORY.NONE')
          } → ${activity.details.new_priority}`;
          break;

        case 'status_changed':
          icon = 'status';
          title = t('KANBAN.HISTORY.STATUS_CHANGED');
          details = `${
            activity.details.old_status || t('KANBAN.HISTORY.PENDING')
          } → ${activity.details.new_status}`;
          break;

        case 'stage_changed':
          icon = 'arrow-right';
          title = t('KANBAN.HISTORY.STAGE_CHANGED');
          const stageUser = activity.details.user || activity.user;
          details = `${getStageName(activity.details.old_stage)} → ${
            getStageName(activity.details.new_stage)
          }${stageUser ? ` (${stageUser.name})` : ''}`;
          break;

        case 'value_changed':
          icon = 'credit-card-person';
          title = t('KANBAN.HISTORY.VALUE_CHANGED');
          const oldValue = activity.details.old_value || '0';
          const newValue = activity.details.new_value;
          const currency = activity.details.currency?.symbol || 'R$';
          details = `${currency} ${oldValue} → ${currency} ${newValue}`;
          break;

        case 'agent_changed':
          icon = 'person';
          title = t('KANBAN.HISTORY.AGENT_CHANGED');
          details = `${
            activity.details.old_agent || t('KANBAN.HISTORY.NONE')
          } → ${activity.details.new_agent || t('KANBAN.HISTORY.NONE')}`;
          break;

        case 'conversation_linked':
          icon = 'chat';
          title = t('KANBAN.HISTORY.CONVERSATION_LINKED');
          const convUser = activity.details.user || activity.user;
          const convId = activity.details.conversation_id || props.item?.item_details?.conversation?.display_id;
          const convTitle = activity.details.conversation_title || props.item?.item_details?.conversation?.last_message?.content || 'Conversa';
          details = `${convUser?.name || t('KANBAN.SYSTEM')} ${t(
            'KANBAN.HISTORY.LINKED_CONVERSATION'
          )} #${convId} - ${convTitle}`;
          break;

        default:
          icon = 'info';
          title = `${t('KANBAN.HISTORY.ACTIVITY')}: ${activity.type}`;
          details = JSON.stringify(activity.details);
      }

      return {
        ...activity,
        icon,
        title,
        details,
      };
    })
    .sort((a, b) => new Date(b.created_at) - new Date(a.created_at)); // Ordena por data decrescente
});

// Função para formatar data de forma compacta
const formatDate = dateString => {
  try {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now - date;
    const diffHours = diffMs / (1000 * 60 * 60);
    const diffDays = diffMs / (1000 * 60 * 60 * 24);

    // Se for hoje, mostra apenas hora
    if (diffHours < 24 && date.toDateString() === now.toDateString()) {
      return date.toLocaleTimeString('pt-BR', {
        hour: '2-digit',
        minute: '2-digit',
      });
    }

    // Se for ontem, mostra "ontem"
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    if (date.toDateString() === yesterday.toDateString()) {
      return 'ontem';
    }

    // Se for nos últimos 7 dias, mostra dia da semana
    if (diffDays < 7) {
      const weekdays = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
      return weekdays[date.getDay()];
    }

    // Caso contrário, mostra dia/mês
    return date.toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
    });
  } catch (error) {
    return dateString;
  }
};
</script>

<template>
  <!-- Container principal com estilo consistente -->
  <div class="activities-container bg-white dark:bg-slate-800 rounded-xl p-4 shadow-sm">
    <!-- Cabeçalho da aba com indicador de pulso -->
    <div class="activities-header flex items-center justify-between mb-4">
      <div class="flex items-center gap-2">
        <div class="w-2 h-2 bg-woot-500 rounded-full animate-pulse"></div>
        <h3 class="text-base font-semibold text-slate-900 dark:text-slate-100">
          {{ t('KANBAN.TABS.ACTIVITIES') }}
        </h3>
      </div>
      <div class="flex items-center gap-2">
        <span class="text-xs text-slate-500 bg-slate-100 dark:bg-slate-700 px-3 py-1 rounded-full font-medium">
          {{ activities.length }} {{ t('KANBAN.HISTORY.ACTIVITIES') }}
        </span>
      </div>
    </div>

    <!-- Mensagem quando não há atividades -->
    <div
      v-if="activities.length === 0"
      class="text-center py-8 text-slate-500 dark:text-slate-400"
    >
      <fluent-icon icon="calendar-clock" size="32" class="mx-auto mb-4 opacity-50" />
      <p class="text-sm">{{ t('KANBAN.HISTORY.NO_ACTIVITY') }}</p>
    </div>

    <!-- Timeline de atividades -->
    <div v-else class="activities-timeline">
      <div
        v-for="(event, index) in history"
        :key="event.id"
        class="activity-item"
      >
        <!-- Ícone e linha de conexão -->
        <div class="activity-connector">
          <div class="activity-icon">
            <fluent-icon :icon="event.icon" size="11" />
          </div>
          <!-- Linha de conexão (não mostrar na última atividade) -->
          <div
            v-if="index < history.length - 1"
            class="activity-line"
          ></div>
        </div>

        <!-- Conteúdo do evento -->
        <div class="activity-content">
          <div class="activity-header">
            <div class="flex items-center gap-2">
              <span class="activity-title">
                {{ event.title }}
              </span>
            </div>
            <span class="activity-date">
              {{ formatDate(event.created_at) }}
            </span>
          </div>

          <div class="activity-details">
            <p class="activity-text">{{ event.details }}</p>
          </div>

          <div v-if="event.user && event.user.name" class="activity-author">
            <Avatar
              :name="event.user.name"
              :src="event.user.avatar_url"
              :size="20"
            />
            <span class="text-xs text-slate-600 dark:text-slate-400">
              {{ event.user.name }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Animações do componente de atividades */
@keyframes fade-in-up {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes activity-pulse {
  0%, 100% { transform: scale(1); opacity: 0.8; }
  50% { transform: scale(1.05); opacity: 1; }
}

/* Container principal */
.activities-container {
  animation: fade-in-up 0.6s ease-out;
}

.activities-header {
  animation: fade-in-up 0.4s ease-out;
}

.activities-timeline {
  @apply relative;
}

.activity-item {
  @apply flex gap-4 mb-3;
}

.activity-connector {
  @apply flex flex-col items-center;
}

.activity-icon {
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  background-color: rgb(241 245 249) !important;
  color: rgb(17 24 39) !important;
  width: 40px !important;
  height: 40px !important;
  padding: 6px !important;
  border-radius: 20px !important;
  box-sizing: border-box !important;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  position: relative;
}

.activity-icon:hover {
  transform: scale(1.1) translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
}

.activity-line {
  @apply w-px h-full bg-slate-200 dark:bg-slate-600 mt-2;
  background: linear-gradient(180deg,
    rgba(148, 163, 184, 0.3),
    rgba(148, 163, 184, 0.6),
    rgba(148, 163, 184, 0.3)
  );
}

/* Dark mode adjustments */
.dark .activity-line {
  background: linear-gradient(180deg,
    rgba(71, 85, 105, 0.3),
    rgba(71, 85, 105, 0.6),
    rgba(71, 85, 105, 0.3)
  );
}

.activity-content {
  @apply flex-1 min-w-0;
}

.activity-header {
  @apply flex items-center justify-between mb-0.5;
}

.activity-title {
  @apply font-medium text-sm text-slate-900 dark:text-slate-100 whitespace-nowrap;
}

.activity-date {
  @apply text-xs text-slate-500 dark:text-slate-400;
}

.activity-details {
  @apply mb-1;
}

.activity-text {
  @apply text-sm text-slate-700 dark:text-slate-300 leading-relaxed;
}

.activity-author {
  @apply flex items-center gap-2;
}

/* Responsive adjustments */
@media (max-width: 768px) {
  .activities-container {
    padding: 1rem;
  }

  .activity-icon {
    width: 2rem !important;
    height: 2rem !important;
  }

  .activity-icon fluent-icon {
    font-size: 0.65rem;
  }

  .activity-item {
    gap: 0.75rem;
    margin-bottom: 0.75rem;
  }
}
</style>
