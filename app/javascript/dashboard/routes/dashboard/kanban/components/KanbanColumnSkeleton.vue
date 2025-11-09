<template>
  <div class="kanban-column-skeleton">
    <!-- Header skeleton -->
    <div class="skeleton-header">
      <div class="skeleton-title" />
      <div class="skeleton-count" />
      <div class="skeleton-actions">
        <div class="skeleton-button" />
        <div class="skeleton-button" />
      </div>
    </div>

    <!-- Items skeleton -->
    <div class="skeleton-items">
      <div v-for="i in 3" :key="i" class="skeleton-item" />
    </div>
  </div>
</template>

<style scoped>
.kanban-column-skeleton {
  min-width: 320px;
  max-width: 350px;
  height: 100%;
  background: #f8fafc;
  border-radius: 0.5rem;
  overflow: hidden;
}

.skeleton-header {
  padding: 0.5rem 1rem;
  background: #f1f5f9;
  border-bottom: 1px solid #e2e8f0;
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.skeleton-title {
  width: 80px;
  height: 16px;
  background: #e2e8f0;
  border-radius: 4px;
  animation: pulse 1.5s ease-in-out infinite;
}

.skeleton-count {
  width: 20px;
  height: 20px;
  background: #e2e8f0;
  border-radius: 50%;
  animation: pulse 1.5s ease-in-out infinite;
}

.skeleton-actions {
  margin-left: auto;
  display: flex;
  gap: 0.25rem;
}

.skeleton-button {
  width: 16px;
  height: 16px;
  background: #e2e8f0;
  border-radius: 2px;
  animation: pulse 1.5s ease-in-out infinite;
}

.skeleton-items {
  padding: 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.skeleton-item {
  width: 100%;
  height: 80px;
  background: #e2e8f0;
  border-radius: 0.5rem;
  animation: pulse 1.5s ease-in-out infinite;
}

@keyframes pulse {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.5;
  }
}

.dark .kanban-column-skeleton {
  background: #1e293b;
}

.dark .skeleton-header {
  background: #334155;
  border-bottom-color: #475569;
}

.dark .skeleton-title,
.dark .skeleton-count,
.dark .skeleton-button,
.dark .skeleton-item {
  background: #475569;
}
</style>
