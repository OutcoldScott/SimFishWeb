//! Generic 2D grid with helpers used by both substrate and chemistry.

#[derive(Clone, Debug)]
pub struct Grid<T> {
    pub width: usize,
    pub height: usize,
    pub cells: Vec<T>,
}

impl<T: Clone + Default> Grid<T> {
    pub fn new(width: usize, height: usize) -> Self {
        Self {
            width,
            height,
            cells: vec![T::default(); width * height],
        }
    }
}

impl<T: Clone> Grid<T> {
    pub fn filled(width: usize, height: usize, value: T) -> Self {
        Self {
            width,
            height,
            cells: vec![value; width * height],
        }
    }
}

impl<T> Grid<T> {
    #[inline]
    pub fn idx(&self, x: usize, y: usize) -> usize {
        debug_assert!(x < self.width && y < self.height);
        y * self.width + x
    }

    #[inline]
    pub fn get(&self, x: usize, y: usize) -> &T {
        &self.cells[self.idx(x, y)]
    }

    #[inline]
    pub fn get_mut(&mut self, x: usize, y: usize) -> &mut T {
        let i = self.idx(x, y);
        &mut self.cells[i]
    }

    #[inline]
    pub fn try_get(&self, x: isize, y: isize) -> Option<&T> {
        if x < 0 || y < 0 || x as usize >= self.width || y as usize >= self.height {
            None
        } else {
            Some(self.get(x as usize, y as usize))
        }
    }
}
