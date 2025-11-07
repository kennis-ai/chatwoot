import kanbanAPI from 'dashboard/api/kanban';
import kanbanConfigAPI from 'dashboard/api/kanbanConfig';
import Vue from 'vue';

export const state = {
  records: {},
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
  config: null,
  selectedFunnelId: null,
  filters: {
    showWon: false,
    showLost: false,
  },
};

export const getters = {
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getKanbanItems: $state => {
    return Object.values($state.records);
  },
  getKanbanItem: $state => id => {
    return $state.records[id];
  },
  getItemsByStage: $state => (funnelId, stage) => {
    let items = Object.values($state.records).filter(
      item => item.funnel_id === funnelId && item.funnel_stage === stage
    );

    // Apply status filters
    if ($state.filters.showWon && !$state.filters.showLost) {
      items = items.filter(item => item.item_details?.status === 'won');
    } else if ($state.filters.showLost && !$state.filters.showWon) {
      items = items.filter(item => item.item_details?.status === 'lost');
    } else if ($state.filters.showWon && $state.filters.showLost) {
      items = items.filter(
        item =>
          item.item_details?.status === 'won' ||
          item.item_details?.status === 'lost'
      );
    }

    return items.sort((a, b) => a.position - b.position);
  },
  getItemsByFunnel: $state => funnelId => {
    return Object.values($state.records).filter(
      item => item.funnel_id === funnelId
    );
  },
  getConfig($state) {
    return $state.config;
  },
  getSelectedFunnelId($state) {
    return $state.selectedFunnelId;
  },
  getFunnels($state) {
    return $state.config?.config?.funnels || [];
  },
  getSelectedFunnel($state, $getters) {
    const funnels = $getters.getFunnels;
    return funnels.find(f => f.id === $state.selectedFunnelId) || funnels[0];
  },
  getFilters($state) {
    return $state.filters;
  },
};

export const actions = {
  async get({ commit }, params = {}) {
    commit('setUIFlags', { isFetching: true });
    try {
      const response = await kanbanAPI.get(params);
      commit('setKanbanItems', response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  async show({ commit }, id) {
    commit('setUIFlags', { isFetching: true });
    try {
      const response = await kanbanAPI.show(id);
      commit('updateKanbanItem', response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  async create({ commit }, itemData) {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await kanbanAPI.create(itemData);
      commit('addKanbanItem', response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  async update({ commit }, { id, ...itemData }) {
    commit('setUIFlags', { isUpdating: true });
    try {
      const response = await kanbanAPI.update(id, itemData);
      commit('updateKanbanItem', response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit('setUIFlags', { isUpdating: false });
    }
  },

  async delete({ commit }, id) {
    commit('setUIFlags', { isDeleting: true });
    try {
      await kanbanAPI.delete(id);
      commit('deleteKanbanItem', id);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit('setUIFlags', { isDeleting: false });
    }
  },

  async move({ commit }, { id, funnel_stage, position }) {
    try {
      const response = await kanbanAPI.move(id, {
        funnel_stage,
        position,
      });
      commit('updateKanbanItem', response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    }
  },

  async reorder({ commit }, { funnelId, funnelStage, itemIds }) {
    try {
      const response = await kanbanAPI.reorder(funnelId, funnelStage, itemIds);
      // Update positions for all items in the response
      if (response.data && response.data.items) {
        response.data.items.forEach(item => {
          commit('updateKanbanItem', item);
        });
      }
      return response.data;
    } catch (error) {
      throw new Error(error);
    }
  },

  async assign({ commit }, { id, agentId }) {
    try {
      const response = await kanbanAPI.assign(id, agentId);
      commit('updateKanbanItem', response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    }
  },

  async bulkMove({ commit }, { itemIds, funnel_stage, position }) {
    try {
      const response = await kanbanAPI.bulkMove(itemIds, {
        funnel_stage,
        position,
      });
      if (response.data && response.data.items) {
        response.data.items.forEach(item => {
          commit('updateKanbanItem', item);
        });
      }
      return response.data;
    } catch (error) {
      throw new Error(error);
    }
  },

  async bulkAssign({ commit }, { itemIds, agentId }) {
    try {
      const response = await kanbanAPI.bulkAssign(itemIds, agentId);
      if (response.data && response.data.items) {
        response.data.items.forEach(item => {
          commit('updateKanbanItem', item);
        });
      }
      return response.data;
    } catch (error) {
      throw new Error(error);
    }
  },

  async duplicate({ commit }, id) {
    try {
      const response = await kanbanAPI.duplicate(id);
      commit('addKanbanItem', response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    }
  },

  async getConfig({ commit }) {
    commit('setUIFlags', { isFetching: true });
    try {
      const response = await kanbanConfigAPI.get();
      commit('setConfig', response.data);
      return response.data;
    } catch (error) {
      // If config doesn't exist, that's okay - user needs to create one
      if (error.response?.status === 404) {
        commit('setConfig', null);
        return null;
      }
      throw new Error(error);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  async updateConfig({ commit }, configData) {
    commit('setUIFlags', { isUpdating: true });
    try {
      const response = await kanbanConfigAPI.update(configData);
      commit('setConfig', response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit('setUIFlags', { isUpdating: false });
    }
  },

  async createConfig({ commit }, configData) {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await kanbanConfigAPI.create(configData);
      commit('setConfig', response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  setSelectedFunnel({ commit }, funnelId) {
    commit('setSelectedFunnel', funnelId);
  },

  toggleWonFilter({ commit, state: $state }) {
    commit('setFilters', { showWon: !$state.filters.showWon });
  },

  toggleLostFilter({ commit, state: $state }) {
    commit('setFilters', { showLost: !$state.filters.showLost });
  },

  async generateWithAI({ commit }, { funnel_id, source, max_items, filters }) {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await kanbanAPI.generateWithAI({
        funnel_id,
        source,
        max_items,
        filters,
      });
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },
};

export const mutations = {
  setUIFlags($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },

  setKanbanItems($state, items) {
    $state.records = items.reduce((acc, item) => {
      acc[item.id] = item;
      return acc;
    }, {});
  },

  addKanbanItem($state, item) {
    Vue.set($state.records, item.id, item);
  },

  updateKanbanItem($state, item) {
    Vue.set($state.records, item.id, {
      ...$state.records[item.id],
      ...item,
    });
  },

  deleteKanbanItem($state, id) {
    Vue.delete($state.records, id);
  },

  setConfig($state, config) {
    $state.config = config;
  },

  setSelectedFunnel($state, funnelId) {
    $state.selectedFunnelId = funnelId;
  },

  setFilters($state, filters) {
    $state.filters = { ...$state.filters, ...filters };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
