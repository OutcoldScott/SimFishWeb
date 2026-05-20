//! Water chemistry: scalar fields with diffusion + reaction.
//!
//! Each tracked species is one f32 grid. Diffusion is implemented as a 4-neighbor
//! averaging step (explicit, stable for small dt and rate). Advection by water
//! flow is not in this crate yet - this is the chemistry layer in isolation.
//!
//! Nitrogen cycle:
//!   NH4 --(nitrosomonas, needs O2)--> NO2
//!   NO2 --(nitrobacter,  needs O2)--> NO3
//!   NO3 --(anaerobic denitrifiers)--> N2 (lost from system)
//!
//! pH is derived each frame from KH, CO2, and tannins (rough approximation).

use crate::grid::Grid;
use crate::substrate::SubstrateSim;

#[derive(Copy, Clone, Debug, Eq, PartialEq, Hash)]
pub enum Species {
    Ammonia,   // NH3 + NH4 lumped, in mg/L
    Nitrite,   // NO2
    Nitrate,   // NO3
    Oxygen,    // O2 dissolved, mg/L
    Co2,       // CO2 dissolved, mg/L
    Tannins,   // unitless 0..1
    Kh,        // carbonate hardness, dKH
    Gh,        // general hardness, dGH
    Iron,      // Fe, mg/L
    Potassium, // K, mg/L
    Phosphate, // PO4, mg/L
}

impl Species {
    pub const ALL: &'static [Species] = &[
        Species::Ammonia,
        Species::Nitrite,
        Species::Nitrate,
        Species::Oxygen,
        Species::Co2,
        Species::Tannins,
        Species::Kh,
        Species::Gh,
        Species::Iron,
        Species::Potassium,
        Species::Phosphate,
    ];

    /// Diffusion rate (per second). Gases diffuse faster than dissolved solids.
    pub fn diffusion_rate(self) -> f32 {
        match self {
            Species::Oxygen | Species::Co2 => 0.25,
            Species::Ammonia => 0.18,
            Species::Nitrite | Species::Nitrate => 0.12,
            Species::Tannins => 0.10,
            Species::Iron | Species::Potassium | Species::Phosphate => 0.08,
            Species::Kh | Species::Gh => 0.06,
        }
    }
}

pub struct ChemistryField {
    pub width: usize,
    pub height: usize,
    fields: Vec<Grid<f32>>,
    /// Scratch buffer for diffusion to avoid per-tick allocation.
    scratch: Grid<f32>,
}

impl ChemistryField {
    pub fn new(width: usize, height: usize) -> Self {
        let fields = Species::ALL
            .iter()
            .map(|_| Grid::filled(width, height, 0.0_f32))
            .collect();
        Self {
            width,
            height,
            fields,
            scratch: Grid::filled(width, height, 0.0),
        }
    }

    fn field_index(s: Species) -> usize {
        Species::ALL.iter().position(|x| *x == s).unwrap()
    }

    pub fn get(&self, s: Species, x: usize, y: usize) -> f32 {
        *self.fields[Self::field_index(s)].get(x, y)
    }

    pub fn set(&mut self, s: Species, x: usize, y: usize, v: f32) {
        let i = Self::field_index(s);
        *self.fields[i].get_mut(x, y) = v.max(0.0);
    }

    pub fn add(&mut self, s: Species, x: usize, y: usize, v: f32) {
        let i = Self::field_index(s);
        let cell = self.fields[i].get_mut(x, y);
        *cell = (*cell + v).max(0.0);
    }

    /// Whole-tank average of a species, restricted to water cells.
    /// Substrate cells contain stale values; including them skews the test-kit reading.
    pub fn average(&self, s: Species, substrate: &SubstrateSim) -> f32 {
        let f = &self.fields[Self::field_index(s)];
        let mut sum = 0.0;
        let mut count = 0usize;
        for y in 0..self.height {
            for x in 0..self.width {
                if substrate.grid.get(x, y).kind.is_empty() {
                    sum += *f.get(x, y);
                    count += 1;
                }
            }
        }
        if count == 0 {
            0.0
        } else {
            sum / count as f32
        }
    }

    /// Derived pH from KH, CO2, tannins. Rough approximation matching aquarist
    /// charts: pH ~ 7.0 + log10(KH/CO2) * 0.5 - tannins * 0.5.
    pub fn ph_at(&self, x: usize, y: usize) -> f32 {
        let kh = self.get(Species::Kh, x, y).max(0.1);
        let co2 = self.get(Species::Co2, x, y).max(0.1);
        let tannins = self.get(Species::Tannins, x, y);
        7.0 + (kh / co2).log10() * 0.5 - tannins * 0.5
    }

    /// Diffuse every species using an explicit 4-neighbor stencil.
    /// Only water cells (substrate kind = Empty) participate.
    ///
    /// alpha is clamped to 0.24 per call for stability. At large dt this caps
    /// diffusion below its specified rate - acceptable, since chemistry advection
    /// from water flow (not modeled here) does most of the long-range mixing.
    pub fn diffuse(&mut self, dt: f32, substrate: &SubstrateSim) {
        let w = self.width;
        let h = self.height;
        for (si, _sp) in Species::ALL.iter().enumerate() {
            let rate = Species::ALL[si].diffusion_rate();
            let alpha = (rate * dt).clamp(0.0, 0.24);
            self.scratch.cells.copy_from_slice(&self.fields[si].cells);
            for y in 0..h {
                for x in 0..w {
                    if !substrate.grid.get(x, y).kind.is_empty() {
                        continue;
                    }
                    let c = *self.scratch.get(x, y);
                    let mut sum = 0.0;
                    let mut count = 0.0;
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nx = x as isize + dx;
                        let ny = y as isize + dy;
                        if self.scratch.try_get(nx, ny).is_some() {
                            let nx = nx as usize;
                            let ny = ny as usize;
                            if substrate.grid.get(nx, ny).kind.is_empty() {
                                sum += *self.scratch.get(nx, ny);
                                count += 1.0;
                            }
                        }
                    }
                    if count > 0.0 {
                        let avg = sum / count;
                        let new = c + alpha * (avg - c);
                        *self.fields[si].get_mut(x, y) = new.max(0.0);
                    }
                }
            }
        }
    }

    /// Surface gas exchange: at the water surface row, O2 trends toward
    /// saturation and CO2 outgasses. `surface_y` is the row index of the
    /// meniscus; `agitation` (0..1) scales the rate (bubbler raises it).
    pub fn surface_exchange(&mut self, surface_y: usize, agitation: f32, dt: f32) {
        let o2_sat = 8.5; // mg/L target at 25C, freshwater.
        let co2_air = 0.5;
        // First-order relaxation toward saturation; clamp the per-tick factor
        // so we never overshoot even at large dt.
        let k_per_sec = 0.0008 + agitation * 0.005;
        let factor = (1.0 - (-k_per_sec * dt).exp()).min(0.9);
        for x in 0..self.width {
            let o2 = self.get(Species::Oxygen, x, surface_y);
            let co2 = self.get(Species::Co2, x, surface_y);
            self.set(Species::Oxygen, x, surface_y, o2 + (o2_sat - o2) * factor);
            self.set(Species::Co2, x, surface_y, co2 + (co2_air - co2) * factor);
        }
    }
}

/// Run nitrogen-cycle bacterial reactions on every substrate cell, mutating
/// chemistry fields in the cells of water *adjacent* to substrate (that's where
/// the biofilm lives + draws from).
///
/// This is the load-bearing function for "tank cycling" — getting the cells
/// to consume ammonia and produce nitrate is the heart of the sim.
pub fn nitrogen_cycle_step(
    chem: &mut ChemistryField,
    substrate: &mut SubstrateSim,
    dt: f32,
) {
    let w = chem.width;
    let h = chem.height;
    // For each substrate cell, find a water cell to its north (typical biofilm
    // facing). We do reactions there, scaled by bacteria population.
    for y in 0..h {
        for x in 0..w {
            let kind = substrate.grid.get(x, y).kind;
            if kind.is_empty() {
                continue;
            }
            // Water cell to consume from = first empty neighbor we find.
            let mut wxy: Option<(usize, usize)> = None;
            for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] {
                let nx = x as isize + dx;
                let ny = y as isize + dy;
                if nx < 0 || ny < 0 || nx as usize >= w || ny as usize >= h {
                    continue;
                }
                let nx = nx as usize;
                let ny = ny as usize;
                if substrate.grid.get(nx, ny).kind.is_empty() {
                    wxy = Some((nx, ny));
                    break;
                }
            }
            let Some((wx, wy)) = wxy else {
                continue;
            };

            let cap = kind.bacterial_capacity();
            let nitrosomonas = substrate.grid.get(x, y).nitrosomonas;
            let nitrobacter = substrate.grid.get(x, y).nitrobacter;
            let nso_pop = nitrosomonas * cap;
            let nbc_pop = nitrobacter * cap;

            // Available substrates for the reactions.
            let nh4 = chem.get(Species::Ammonia, wx, wy);
            let no2 = chem.get(Species::Nitrite, wx, wy);
            let no3 = chem.get(Species::Nitrate, wx, wy);
            let o2 = chem.get(Species::Oxygen, wx, wy);

            // Aerobic reactions need O2; their rate is gated by it via
            // Michaelis-Menten on a half-saturation constant.
            let o2_factor = o2 / (o2 + 1.0);

            // Cap fraction-consumed-per-tick for integrator stability.
            const MAX_FRAC_PER_TICK: f32 = 0.2;

            // Rate constants. The factor of 5x over the baseline accounts for
            // the fact that real tanks have biofilm distributed over far more
            // surface than our top-row-only reaction model captures. Tune
            // these once a richer biofilm distribution lands.
            let raw_nh4 = 0.10 * nso_pop * o2_factor * nh4 / (nh4 + 0.5) * dt;
            let r_nh4 = raw_nh4.min(nh4 * MAX_FRAC_PER_TICK);
            let raw_no2 = 0.12 * nbc_pop * o2_factor * no2 / (no2 + 0.2) * dt;
            let r_no2 = raw_no2.min(no2 * MAX_FRAC_PER_TICK);

            let anaero = substrate.grid.get(x, y).anaerobic;
            let raw_no3 = 0.015 * nso_pop * anaero * no3 / (no3 + 1.0) * dt;
            let r_no3 = raw_no3.min(no3 * MAX_FRAC_PER_TICK);

            chem.add(Species::Ammonia,  wx, wy, -r_nh4);
            chem.add(Species::Nitrite,  wx, wy,  r_nh4 - r_no2);
            chem.add(Species::Nitrate,  wx, wy,  r_no2 - r_no3);
            chem.add(Species::Oxygen,   wx, wy, -(r_nh4 + r_no2) * 1.5);

            // Bacterial growth: each population grows on its own food and
            // decays slowly when starved. Nitrobacter is slower to establish
            // because its food (NO2) only appears once nitrosomonas runs - that
            // lag is what creates the nitrite spike in the cycle.
            let nso_growth = nh4 / (nh4 + 0.5) * 0.0006 * o2_factor - 0.00003;
            let nbc_growth = no2 / (no2 + 0.5) * 0.00035 * o2_factor - 0.00003;
            let cell = substrate.grid.get_mut(x, y);
            cell.nitrosomonas = (cell.nitrosomonas + nso_growth * dt).clamp(0.0, 1.0);
            cell.nitrobacter  = (cell.nitrobacter  + nbc_growth * dt).clamp(0.0, 1.0);
        }
    }
}
