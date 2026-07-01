# Social Network Project TODO

## Phase 1: Database Schema & tRPC Procedures
- [x] Create database schema: users, posts, comments, likes, follows
- [x] Create tRPC procedures for posts (create, list, delete)
- [x] Create tRPC procedures for comments (create, list, delete, reply)
- [x] Create tRPC procedures for likes/reactions
- [x] Create tRPC procedures for user profile and follows

## Phase 2: Authentication & User Profile
- [x] Implement user login/logout with Manus OAuth
- [x] Create user profile page component
- [x] Display user avatar and name in header
- [x] Add follower/following counts on profile
- [ ] Create profile edit functionality

## Phase 3: Post Creation & Media Upload
- [ ] Build post composer component with text input
- [ ] Implement photo upload functionality
- [ ] Implement video upload functionality
- [ ] Create post preview before publishing
- [ ] Ensure text input is visible in both light and dark themes
- [ ] Add post deletion functionality

## Phase 4: Comment System with Nested Replies
- [ ] Create comment input component with Send button
- [ ] Implement comment submission
- [ ] Display comments under posts in threaded format
- [ ] Implement reply-to-comment functionality (Facebook-style)
- [ ] Ensure comment input is visible in both themes
- [ ] Add comment deletion functionality
- [ ] Add nested reply display (indentation/threading)

## Phase 5: Discovery Column with Auto-Scroll
- [ ] Create discovery sidebar component
- [ ] Implement random post fetching
- [ ] Add auto-scroll every 7 seconds
- [ ] Display post author profile info in discovery
- [ ] Display like count in discovery
- [ ] Add click-to-profile navigation
- [ ] Handle edge cases (empty feed, single post)

## Phase 6: Like/Reaction System
- [ ] Implement like button on posts
- [ ] Implement like button on comments
- [ ] Display like count
- [ ] Add reaction emoji selector (optional)
- [ ] Implement unlike functionality
- [ ] Add visual feedback for liked items

## Phase 7: Media Modal Viewer
- [ ] Create lightbox/modal component
- [ ] Implement previous/next navigation
- [ ] Add keyboard support (arrow keys, Escape)
- [ ] Display media counter (X of Y)
- [ ] Handle single vs multiple media
- [ ] Add close button

## Phase 8: Dark Mode with Perfect Contrast
- [ ] Verify all text inputs have correct contrast in light mode
- [ ] Verify all text inputs have correct contrast in dark mode
- [ ] Fix post composer text visibility
- [ ] Fix comment input text visibility
- [ ] Verify all UI elements have proper colors in both themes
- [ ] Test theme switching
- [ ] Add theme toggle in header

## Phase 9: Security & Environment Variables
- [ ] Configure Supabase keys as server-side env variables
- [ ] Ensure secret keys never reach client bundle
- [ ] Implement secure API communication
- [ ] Add environment variable validation
- [ ] Create .env.example file
- [ ] Document security setup

## Phase 10: Testing, Optimization & Delivery
- [ ] Write unit tests for core procedures
- [ ] Test responsive layout on mobile/tablet
- [ ] Optimize performance (lazy loading, pagination)
- [ ] Test dark mode switching
- [ ] Test all user flows
- [ ] Create checkpoint for deployment
- [ ] Document setup and deployment instructions
