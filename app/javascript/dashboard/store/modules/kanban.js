import KanbanAPI from '../../api/kanban';

const state = {
  items: {}, // keyed by stage ID: { stageId: [items...] }
  selectedItem: null,
  loading: false,
  error: null,
};

const getters = {
  getKanbanItems: state => state.items,
  getItemsByStage: state => stageId => state.items[stageId] || [],
  getItemById: state => id => {
    for (const stageItems of Object.values(state.items)) {
      const item = stageItems.find(i => i.id === id);
      if (item) return item;
    }
    return null;
  },
  getAllItems: state => {
    return Object.values(state.items).flat();
  },
  isLoading: state => state.loading,
  getError: state => state.error,
  getSelectedItem: state => state.selectedItem,
};

const actions = {
  async fetchKanbanItems({ commit }, { stageId, funnelId, page = 1 }) {
    commit('SET_LOADING', true);
    try {
      const response = await KanbanAPI.getItems({
        funnel_id: funnelId,
        stage_id: stageId,
        page,
      });
      commit('SET_ITEMS', {
        stageId,
        items: response.data.items || response.data,
      });
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    } finally {
      commit('SET_LOADING', false);
    }
  },

  async fetchKanbanItem({ commit }, itemId) {
    try {
      const response = await KanbanAPI.getItem(itemId);
      commit('UPDATE_ITEM', response.data);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async createKanbanItem({ commit }, itemData) {
    try {
      const response = await KanbanAPI.createItem(itemData);
      commit('ADD_ITEM', {
        stageId: itemData.funnel_stage,
        item: response.data,
      });
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async updateKanbanItem({ commit }, { id, data }) {
    try {
      const response = await KanbanAPI.updateItem(id, data);
      commit('UPDATE_ITEM', response.data);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async deleteKanbanItem({ commit }, id) {
    try {
      await KanbanAPI.deleteItem(id);
      commit('REMOVE_ITEM', id);
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async moveItemToStage({ commit }, { itemId, fromStage, toStage }) {
    try {
      const response = await KanbanAPI.moveToStage(itemId, toStage);
      commit('MOVE_ITEM', {
        itemId,
        fromStage,
        toStage,
        updatedItem: response.data,
      });
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async reorderItems({ commit }, { stageId, itemIds }) {
    try {
      await KanbanAPI.reorder(stageId, itemIds);
      commit('REORDER_ITEMS', { stageId, itemIds });
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async searchItems({ commit }, { query, funnelId }) {
    try {
      const response = await KanbanAPI.search(query, funnelId);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async filterItems({ commit }, params) {
    try {
      const response = await KanbanAPI.filter(params);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async getReports({ commit }, params) {
    try {
      const response = await KanbanAPI.getReports(params);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async createChecklistItem({ commit }, { itemId, data }) {
    try {
      const response = await KanbanAPI.createChecklistItem(itemId, data);
      commit('UPDATE_ITEM', response.data);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async deleteChecklistItem({ commit }, { itemId, checklistItemId }) {
    try {
      const response = await KanbanAPI.deleteChecklistItem(
        itemId,
        checklistItemId
      );
      commit('UPDATE_ITEM', response.data);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async createNote({ commit }, { itemId, data }) {
    try {
      const response = await KanbanAPI.createNote(itemId, data);
      commit('UPDATE_ITEM', response.data);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async deleteNote({ commit }, { itemId, noteId }) {
    try {
      const response = await KanbanAPI.deleteNote(itemId, noteId);
      commit('UPDATE_ITEM', response.data);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async bulkMoveItems({ commit }, { itemIds, toStage }) {
    try {
      await KanbanAPI.bulkMoveItems(itemIds, toStage);
      // Refresh items after bulk operation
      return true;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async bulkAssignAgent({ commit }, { itemIds, agentId }) {
    try {
      await KanbanAPI.bulkAssignAgent(itemIds, agentId);
      return true;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async bulkSetPriority({ commit }, { itemIds, priority }) {
    try {
      await KanbanAPI.bulkSetPriority(itemIds, priority);
      return true;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  setSelectedItem({ commit }, item) {
    commit('SET_SELECTED_ITEM', item);
  },

  clearItems({ commit }) {
    commit('CLEAR_ITEMS');
  },
};

const mutations = {
  SET_ITEMS(state, { stageId, items }) {
    state.items = { ...state.items, [stageId]: items };
  },

  ADD_ITEM(state, { stageId, item }) {
    const stageItems = state.items[stageId] || [];
    state.items = {
      ...state.items,
      [stageId]: [...stageItems, item],
    };
  },

  UPDATE_ITEM(state, updatedItem) {
    for (const [stageId, items] of Object.entries(state.items)) {
      const index = items.findIndex(i => i.id === updatedItem.id);
      if (index !== -1) {
        const newItems = [...items];
        newItems[index] = updatedItem;
        state.items = { ...state.items, [stageId]: newItems };
        break;
      }
    }

    // Update selected item if it's the same one
    if (state.selectedItem?.id === updatedItem.id) {
      state.selectedItem = updatedItem;
    }
  },

  REMOVE_ITEM(state, itemId) {
    for (const [stageId, items] of Object.entries(state.items)) {
      const filtered = items.filter(i => i.id !== itemId);
      if (filtered.length !== items.length) {
        state.items = { ...state.items, [stageId]: filtered };
        break;
      }
    }

    // Clear selected item if it was deleted
    if (state.selectedItem?.id === itemId) {
      state.selectedItem = null;
    }
  },

  MOVE_ITEM(state, { itemId, fromStage, toStage, updatedItem }) {
    // Remove from old stage
    const fromItems = state.items[fromStage] || [];
    const item = fromItems.find(i => i.id === itemId);
    const filteredFrom = fromItems.filter(i => i.id !== itemId);

    // Add to new stage
    const toItems = state.items[toStage] || [];

    state.items = {
      ...state.items,
      [fromStage]: filteredFrom,
      [toStage]: [...toItems, updatedItem || item],
    };
  },

  REORDER_ITEMS(state, { stageId, itemIds }) {
    const items = state.items[stageId] || [];
    const reordered = itemIds
      .map(id => items.find(i => i.id === id))
      .filter(Boolean);
    state.items = { ...state.items, [stageId]: reordered };
  },

  SET_LOADING(state, loading) {
    state.loading = loading;
  },

  SET_ERROR(state, error) {
    state.error = error;
  },

  SET_SELECTED_ITEM(state, item) {
    state.selectedItem = item;
  },

  CLEAR_ITEMS(state) {
    state.items = {};
    state.selectedItem = null;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
