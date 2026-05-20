//! Substrate cellular automaton.
//!
//! Each cell is either empty (water above) or one of several substrate kinds.
//! On each tick we sweep bottom-up and apply falling-sand rules: gravity, slip
//! at angle of repose, compaction by overburden. Bacterial colony counts ride
//! along on the cell - they get destroyed if their host cell is disturbed.
//!
//! Substrate kinds carry chemistry traits (CEC, leaching, anaerobic potential)
//! that the world step reads to drive nutrient release.

use crate::grid::Grid;
use rand::Rng;
use rand_xoshiro::Xoshiro256StarStar;

#[derive(Copy, Clone, Debug, Eq, PartialEq, Default)]
pub enum SubstrateKind {
    #[default]
    Empty,
    Aquasoil,
    Gravel,
    Sand,
    Clay,
    LavaRock,
    Driftwood,
    Stone,
}

impl SubstrateKind {
    /// Cation exchange capacity proxy. Higher -> holds and trades nutrients.
    pub fn cec(self) -> f32 {
        match self {
            SubstrateKind::Aquasoil => 1.0,
            SubstrateKind::Clay => 0.7,
            SubstrateKind::LavaRock => 0.25,
            SubstrateKind::Sand => 0.05,
            SubstrateKind::Gravel | SubstrateKind::Stone | SubstrateKind::Driftwood => 0.0,
            SubstrateKind::Empty => 0.0,
        }
    }

    /// How readily this kind goes anaerobic when buried + still.
    /// Sand compacts and goes anaerobic fast; gravel never does.
    pub fn anaerobic_susceptibility(self) -> f32 {
        match self {
            SubstrateKind::Sand => 1.0,
            SubstrateKind::Aquasoil => 0.6,
            SubstrateKind::Clay => 0.5,
            SubstrateKind::LavaRock => 0.1,
            SubstrateKind::Gravel => 0.0,
            SubstrateKind::Stone | SubstrateKind::Driftwood => 0.0,
            SubstrateKind::Empty => 0.0,
        }
    }

    /// Bacterial surface area per cell - lava rock is the bio-battery.
    pub fn bacterial_capacity(self) -> f32 {
        match self {
            SubstrateKind::LavaRock => 4.0,
            SubstrateKind::Aquasoil => 2.0,
            SubstrateKind::Gravel => 1.5,
            SubstrateKind::Sand => 1.0,
            SubstrateKind::Clay => 1.2,
            SubstrateKind::Driftwood => 2.5,
            SubstrateKind::Stone => 0.7,
            SubstrateKind::Empty => 0.0,
        }
    }

    /// Solid kinds don't fall (rocks, driftwood you placed).
    pub fn is_solid(self) -> bool {
        matches!(self, SubstrateKind::Stone | SubstrateKind::Driftwood)
    }

    /// Empty cell = water column.
    pub fn is_empty(self) -> bool {
        matches!(self, SubstrateKind::Empty)
    }
}

#[derive(Clone, Debug, Default)]
pub struct SubstrateCell {
    pub kind: SubstrateKind,
    /// 0..1, how compacted the cell is (drives anaerobic + slip resistance).
    pub compaction: f32,
    /// Nitrosomonas population 0..1 (saturation fraction of capacity).
    /// Eats NH4 -> NO2. Establishes quickly.
    pub nitrosomonas: f32,
    /// Nitrobacter population 0..1. Eats NO2 -> NO3.
    /// Establishes SLOWER than nitrosomonas - that's why real cycles have a
    /// nitrite spike. Needs NO2 to exist before it can grow, which only
    /// happens once nitrosomonas is established.
    pub nitrobacter: f32,
    /// Detritus mass accumulated in this cell.
    pub detritus: f32,
    /// Anaerobic fraction 0..1, only meaningful for non-empty cells.
    pub anaerobic: f32,
}

pub struct SubstrateSim {
    pub grid: Grid<SubstrateCell>,
}

impl SubstrateSim {
    pub fn new(width: usize, height: usize) -> Self {
        Self {
            grid: Grid::new(width, height),
        }
    }

    /// One falling-sand tick. Sweep bottom-up so falling cells don't cascade
    /// twice in one frame. `dt` is in seconds.
    pub fn step(&mut self, dt: f32, rng: &mut Xoshiro256StarStar) {
        let w = self.grid.width;
        let h = self.grid.height;
        // Bottom-up: y from h-2 to 0 (y=h-1 is floor, never falls).
        for y in (0..h - 1).rev() {
            // Alternate left->right / right->left to avoid bias drift.
            let left_first = (y & 1) == 0;
            let xs: Box<dyn Iterator<Item = usize>> = if left_first {
                Box::new(0..w)
            } else {
                Box::new((0..w).rev())
            };
            for x in xs {
                self.try_fall(x, y, rng);
            }
        }
        // Compaction + anaerobic accumulation: any cell with substrate above it
        // compacts faster, and a compacted susceptible cell goes anaerobic.
        for y in 0..h {
            for x in 0..w {
                let above_solid = y > 0 && !self.grid.get(x, y - 1).kind.is_empty();
                let cell = self.grid.get_mut(x, y);
                if cell.kind.is_empty() {
                    continue;
                }
                if above_solid {
                    cell.compaction = (cell.compaction + 0.05 * dt).min(1.0);
                }
                let target_anaero = cell.compaction * cell.kind.anaerobic_susceptibility();
                // Lerp anaerobic fraction toward its target on a slow timescale.
                cell.anaerobic += (target_anaero - cell.anaerobic) * (0.02 * dt).min(1.0);
            }
        }
    }

    /// Try to make cell (x, y) fall down or slip diagonally.
    fn try_fall(&mut self, x: usize, y: usize, rng: &mut Xoshiro256StarStar) {
        let cell = self.grid.get(x, y).clone();
        if cell.kind.is_empty() || cell.kind.is_solid() {
            return;
        }
        // Straight down first.
        if self.grid.get(x, y + 1).kind.is_empty() {
            self.swap(x, y, x, y + 1);
            return;
        }
        // Slip at angle of repose. Tightly compacted cells resist slip.
        let slip_chance = (1.0 - cell.compaction) * 0.6;
        if rng.gen::<f32>() > slip_chance {
            return;
        }
        let prefer_left = rng.gen::<bool>();
        let mut dxs = [-1i32, 1];
        if !prefer_left {
            dxs.swap(0, 1);
        }
        for &dx in &dxs {
            let nx = x as i32 + dx;
            if nx < 0 || nx as usize >= self.grid.width {
                continue;
            }
            let nx = nx as usize;
            if self.grid.get(nx, y + 1).kind.is_empty() {
                self.swap(x, y, nx, y + 1);
                return;
            }
        }
    }

    fn swap(&mut self, x1: usize, y1: usize, x2: usize, y2: usize) {
        let i1 = self.grid.idx(x1, y1);
        let i2 = self.grid.idx(x2, y2);
        self.grid.cells.swap(i1, i2);
        // Falling disturbs compaction + kills some bacteria.
        let c = &mut self.grid.cells[i2];
        c.compaction *= 0.7;
        c.nitrosomonas *= 0.5;
        c.nitrobacter *= 0.5;
        c.anaerobic *= 0.3;
    }

    /// Convenience: place a slab of substrate from (x0, y0) to (x1, y1) inclusive.
    /// Seed with a tiny dormant bacterial population on both reactions - real tap
    /// water has trace bacteria that colonize given food.
    pub fn fill_region(&mut self, kind: SubstrateKind, x0: usize, y0: usize, x1: usize, y1: usize) {
        for y in y0..=y1.min(self.grid.height - 1) {
            for x in x0..=x1.min(self.grid.width - 1) {
                let c = self.grid.get_mut(x, y);
                c.kind = kind;
                c.nitrosomonas = 0.01;
                c.nitrobacter = 0.005;
            }
        }
    }
}
