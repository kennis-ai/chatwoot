/* global axios */
import ApiClient from './ApiClient';

class KanbanAPI extends ApiClient {
  constructor() {
    super('kanban_items', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(itemData) {
    return axios.post(this.url, itemData);
  }

  update(id, itemData) {
    return axios.patch(`${this.url}/${id}`, itemData);
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // Move item to a different stage
  move(id, { funnel_stage, position }) {
    return axios.post(`${this.url}/${id}/move`, {
      funnel_stage,
      position,
    });
  }

  // Reorder items within a stage
  reorder(funnelId, funnelStage, itemIds) {
    return axios.post(`${this.url}/reorder`, {
      funnel_id: funnelId,
      funnel_stage: funnelStage,
      item_ids: itemIds,
    });
  }

  // Assign agent to item
  assign(id, agentId) {
    return axios.post(`${this.url}/${id}/assign`, {
      agent_id: agentId,
    });
  }

  // Bulk operations
  bulkMove(itemIds, { funnel_stage, position }) {
    return axios.post(`${this.url}/bulk_move_items`, {
      item_ids: itemIds,
      funnel_stage,
      position,
    });
  }

  bulkAssign(itemIds, agentId) {
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

  bulkDelete(itemIds) {
    return axios.post(`${this.url}/bulk_delete`, {
      item_ids: itemIds,
    });
  }

  // Search and filter
  search(query) {
    return axios.get(`${this.url}/search`, {
      params: { q: query },
    });
  }

  filter(filterParams) {
    return axios.get(`${this.url}/filter`, {
      params: filterParams,
    });
  }

  // Reports
  getReports(params = {}) {
    return axios.get(`${this.url}/reports`, { params });
  }

  // Duplicate item
  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  // Label management
  addLabel(id, labelId) {
    return axios.post(`${this.url}/${id}/add_label`, {
      label_id: labelId,
    });
  }

  removeLabel(id, labelId) {
    return axios.post(`${this.url}/${id}/remove_label`, {
      label_id: labelId,
    });
  }

  // AI Generation
  generateWithAI({ funnel_id, source, max_items, filters }) {
    return axios.post(`${this.url}/generate_with_ai`, {
      funnel_id,
      source,
      max_items,
      filters,
    });
  }
}

export default new KanbanAPI();
