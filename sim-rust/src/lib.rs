//! Vivarium core simulation.
//!
//! Three coupled systems on a shared 2D grid:
//!   - Substrate (falling-sand cellular automaton)
//!   - Chemistry (scalar fields with diffusion + advection)
//!   - Biology  (bacterial colonies on substrate surfaces; nitrogen cycle reactions)
//!
//! Deterministic given a seed. Fixed-step `tick(dt)` advances all three.
//!
//! See `examples/cycle.rs` for a runnable demo that prints a tank cycle over time.

pub mod chemistry;
pub mod grid;
pub mod substrate;
pub mod world;

pub use chemistry::{ChemistryField, Species};
pub use grid::Grid;
pub use substrate::{SubstrateCell, SubstrateKind};
pub use world::World;
