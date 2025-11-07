import { frontendURL } from '../../../helper/URLHelper';

const KanbanBoard = () => import('./pages/KanbanBoard.vue');
const KanbanSettings = () => import('./pages/KanbanSettings.vue');
const KanbanTemplates = () => import('./pages/KanbanTemplates.vue');

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/kanban'),
      name: 'kanban_board',
      meta: {
        permissions: ['administrator', 'agent'],
      },
      component: KanbanBoard,
    },
    {
      path: frontendURL('accounts/:accountId/kanban/settings'),
      name: 'kanban_settings',
      meta: {
        permissions: ['administrator'],
      },
      component: KanbanSettings,
    },
    {
      path: frontendURL('accounts/:accountId/kanban/templates'),
      name: 'kanban_templates',
      meta: {
        permissions: ['administrator', 'agent'],
      },
      component: KanbanTemplates,
    },
  ],
};
