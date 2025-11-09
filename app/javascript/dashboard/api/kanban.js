/* global axios */
import ApiClient from './ApiClient';

class KanbanAPI extends ApiClient {
  constructor() {
    super('kanban_items', { accountScoped: true });
  }

  getItems(params) {
    return axios.get(`${this.url}`, { params });
  }

  getItem(id) {
    return axios.get(`${this.url}/${id}`);
  }

  createItem(data) {
    return axios.post(this.url, { kanban_item: data });
  }

  updateItem(id, data) {
    return axios.patch(`${this.url}/${id}`, { kanban_item: data });
  }

  deleteItem(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  moveToStage(id, stageId) {
    return axios.post(`${this.url}/${id}/move_to_stage`, {
      funnel_stage: stageId,
    });
  }

  move(id, data) {
    return axios.post(`${this.url}/${id}/move`, data);
  }

  reorder(stageId, itemIds) {
    return axios.post(`${this.url}/reorder`, {
      funnel_stage: stageId,
      item_ids: itemIds,
    });
  }

  search(query, funnelId) {
    return axios.get(`${this.url}/search`, {
      params: { query, funnel_id: funnelId },
    });
  }

  filter(params) {
    return axios.get(`${this.url}/filter`, { params });
  }

  getReports(params) {
    return axios.get(`${this.url}/reports`, { params });
  }

  debug() {
    return axios.get(`${this.url}/debug`);
  }

  // Checklist operations
  createChecklistItem(itemId, data) {
    return axios.post(`${this.url}/${itemId}/create_checklist_item`, data);
  }

  getChecklist(itemId) {
    return axios.get(`${this.url}/${itemId}/get_checklist`);
  }

  deleteChecklistItem(itemId, checklistItemId) {
    return axios.delete(`${this.url}/${itemId}/delete_checklist_item`, {
      params: { checklist_item_id: checklistItemId },
    });
  }

  // Notes operations
  createNote(itemId, data) {
    return axios.post(`${this.url}/${itemId}/create_note`, data);
  }

  getNotes(itemId) {
    return axios.get(`${this.url}/${itemId}/get_notes`);
  }

  deleteNote(itemId, noteId) {
    return axios.delete(`${this.url}/${itemId}/delete_note`, {
      params: { note_id: noteId },
    });
  }

  // Bulk operations
  bulkMoveItems(itemIds, toStage) {
    return axios.post(`${this.url}/bulk_move_items`, {
      item_ids: itemIds,
      funnel_stage: toStage,
    });
  }

  bulkAssignAgent(itemIds, agentId) {
    return axios.post(`${this.url}/bulk_assign_agent`, {
      item_ids: itemIds,
      agent_id: agentId,
    });
  }

  bulkSetPriority(itemIds, priority) {
    return axios.post(`${this.url}/bulk_set_priority`, {
      item_ids: itemIds,
      priority,
    });
  }
}

export default new KanbanAPI();
