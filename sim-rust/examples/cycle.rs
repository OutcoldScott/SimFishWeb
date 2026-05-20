//! Watch a tank cycle in your terminal.
//!
//! Sets up a fresh aquasoil + gravel tank, doses 2 mg/L ammonia, then runs
//! enough sim ticks to span ~6 simulated weeks at a coarse step. Prints
//! avg NH3 / NO2 / NO3 / O2 / pH and total bacteria biomass each "day".
//!
//! Expected behavior:
//!   - Days 0-4 : ammonia stays high, nitrite starts climbing
//!   - Days 5-12: ammonia falls, nitrite peaks, nitrate begins to climb
//!   - Days 13+ : ammonia ~0, nitrite ~0, nitrate climbs steadily, bacteria stable
//!
//! Run with:
//!     cargo run --release --example cycle

use vivarium_sim::{Species, World};

fn main() {
    // Coarse grid for terminal demo. The shader pipeline uses 288x144.
    let mut world = World::new(64, 48, /* seed */ 0xCAFEF155);
    world.seed_starter_tank();
    world.agitation = 0.3; // gentle bubbler

    // 1 sim-day = 288 ticks of dt=300 sim-seconds = 86400s = 24 sim hours.
    // The integrator is explicit so we keep dt small enough that
    // reaction-per-tick is well under each Michaelis-Menten half-saturation.
    let ticks_per_day = 288;
    let dt = 300.0; // sim seconds per tick (5 sim minutes)

    println!(
        "{:>4} | {:>7} {:>7} {:>7} | {:>5} {:>6} | {:>7} {:>7}",
        "day", "NH3", "NO2", "NO3", "O2", "pH", "Nso", "Nbc"
    );
    println!("{}", "-".repeat(68));

    for day in 0..=42 {
        for _ in 0..ticks_per_day {
            world.tick(dt);
        }
        let nh3 = world.chem.average(Species::Ammonia, &world.substrate);
        let no2 = world.chem.average(Species::Nitrite, &world.substrate);
        let no3 = world.chem.average(Species::Nitrate, &world.substrate);
        let o2 = world.chem.average(Species::Oxygen, &world.substrate);
        let ph = world.average_ph();
        let (nso, nbc) = world.total_bacteria();
        println!(
            "{:>4} | {:>7.3} {:>7.3} {:>7.3} | {:>5.2} {:>6.2} | {:>7.1} {:>7.1}",
            day, nh3, no2, no3, o2, ph, nso, nbc
        );

        // Roughly day 21: simulate adding a fish - dose a small ammonia bump.
        if day == 21 {
            for y in world.surface_y..world.chem.height {
                for x in 0..world.chem.width {
                    if world.substrate.grid.get(x, y).kind.is_empty() {
                        world.chem.add(Species::Ammonia, x, y, 0.5);
                    }
                }
            }
            println!("    > added a fish (ammonia bump)");
        }
    }
}
